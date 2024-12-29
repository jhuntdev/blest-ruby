require 'json'
require 'concurrent'
require 'securerandom'
require 'net/http'



class Router
  attr_reader :routes

  def initialize(options = nil)
    @middleware = []
    @afterware = []
    @timeout = 5000
    @introspection = false
    @routes = {}

    if options
      @timeout = options['timeout'] || options[:timeout] || 5000
      @introspection = options['introspection'] || options[:introspection] || false
    end
  end

  def before(&handler)
    unless handler.is_a?(Proc)
      raise ArgumentError, 'Before handlers should be procs'
    end

    arg_count = handler.arity
    if arg_count <= 2
      @middleware.push(handler)
    else
      raise ArgumentError, 'Before handlers should have at most three arguments'
    end
  end

  def after(&handler)
    unless handler.is_a?(Proc)
      raise ArgumentError, 'After handlers should be procs'
    end

    arg_count = handler.arity
    if arg_count <= 2
      @afterware.push(handler)
    else
      raise ArgumentError, 'After handlers should have at most two arguments'
    end
  end

  def route(route, &handler)
    route_error = validate_route(route, false)
    raise ArgumentError, route_error if route_error
    raise ArgumentError, 'Route already exists' if @routes.key?(route)
    raise ArgumentError, 'Handler should be a function' unless handler.respond_to?(:call)

    @routes[route] = {
      handler: [*@middleware, handler, *@afterware],
      description: nil,
      schema: nil,
      visible: @introspection,
      validate: false,
      timeout: @timeout
    }
  end

  def describe(route, config)
    raise ArgumentError, 'Route does not exist' unless @routes.key?(route)
    raise ArgumentError, 'Configuration should be an object' unless config.is_a?(Hash)

    if config.key?('description')
      raise ArgumentError, 'Description should be a str' if !config['description'].nil? && !config['description'].is_a?(String)
      @routes[route]['description'] = config['description']
    end

    if config.key?('schema')
      raise ArgumentError, 'Schema should be a dict' if !config['schema'].nil? && !config['schema'].is_a?(Hash)
      @routes[route]['schema'] = config['schema']
    end

    if config.key?('visible')
      raise ArgumentError, 'Visible should be True or False' if !config['visible'].nil? && ![true, false].include?(config['visible'])
      @routes[route]['visible'] = config['visible']
    end

    if config.key?('validate')
      raise ArgumentError, 'Validate should be True or False' if !config['validate'].nil? && ![true, false].include?(config['validate'])
      @routes[route]['validate'] = config['validate']
    end

    if config.key?('timeout')
      raise ArgumentError, 'Timeout should be a positive int' if !config['timeout'].nil? && (!config['timeout'].is_a?(Integer) || config['timeout'] <= 0)
      @routes[route]['timeout'] = config['timeout']
    end
  end

  def merge(router)
    raise ArgumentError, 'Router is required' unless router.is_a?(Router)

    new_routes = router.routes.keys
    existing_routes = @routes.keys

    raise ArgumentError, 'No routes to merge' if new_routes.empty?

    new_routes.each do |route|
      if existing_routes.include?(route)
        raise ArgumentError, 'Cannot merge duplicate routes: ' + route
      else
        @routes[route] = {
          **router.routes[route],
          handler: @middleware + router.routes[route][:handler] + @afterware,
          timeout: router.routes[route][:timeout] ||  @timeout
        }
      end
    end
  end

  def namespace(prefix, router)
    raise ArgumentError, 'Router is required' unless router.is_a?(Router)

    prefix_error = validate_route(prefix, false)
    raise ArgumentError, prefix_error if prefix_error

    new_routes = router.routes.keys
    existing_routes = @routes.keys

    raise ArgumentError, 'No routes to namespace' if new_routes.empty?

    new_routes.each do |route|
      ns_route = "#{prefix}/#{route}"
      if existing_routes.include?(ns_route)
        raise ArgumentError, 'Cannot merge duplicate routes: ' + ns_route
      else
        @routes[ns_route] = {
          **router.routes[route],
          handler: @middleware + router.routes[route][:handler] + @afterware,
          timeout: router.routes[route].fetch('timeout', @timeout)
        }
      end
    end
  end

  def handle(request, context = {})
    handle_request(@routes, request, context)
  end

end



class HttpClient
  attr_reader :queue, :futures
  attr_accessor :url, :max_batch_size, :buffer_delay, :headers

  def initialize(url, max_batch_size = 25, buffer_delay = 10, http_headers = {})
    @url = url
    @max_batch_size = max_batch_size
    @buffer_delay = buffer_delay
    @http_headers = http_headers
    @queue = Queue.new
    @futures = {}
    @lock = Mutex.new
  end

  def request(route, body=nil, headers=nil)
    uuid = SecureRandom.uuid()
    future = Concurrent::Promises.resolvable_future
    @lock.synchronize do
      @futures[uuid] = future
    end

    @queue.push({ uuid: uuid, data: [uuid, route, body, headers] })
    process_timeout()
    future
  end

  private

  def process_timeout
    Thread.new do
      sleep @buffer_delay / 1000.0
      process
    end
  end

  def process
    until @queue.empty?
      batch = []
      batch << @queue.pop until batch.length >= @max_batch_size || @queue.empty?

      unless batch.empty?
        response = send_batch(batch)
        process_response(response)
      end
    end
  end

  def send_batch(batch)
    uri = URI(@url)
    path = uri.path
    path = '/' if uri.path.empty?
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'

    request = Net::HTTP::Post.new(path, @http_headers.merge({ 'Accept' => 'application/json', 'Content-Type' => 'application/json' }))
    request.body = JSON.generate(batch.map { |item| item[:data] })

    http.request(request)
  end

  def process_response(response)
    if response.is_a?(Net::HTTPSuccess)
      
      results = JSON.parse(response.body)
      results.each do |result|
        uuid = result[0]
        data = result[2]
        error = result[3]
        future = nil

        @lock.synchronize do
          future = @futures.delete(uuid)
        end

        if future
          if error
            future.reject(error)
          else
            future.fulfill(data)
          end
        end
      end

    else
      @lock.synchronize do
        future = @futures.delete(uuid)
      end

      if future
        error_message = "HTTP Error: #{response.code} - #{response.message}"
        future.reject(error_message)
      end
    end
  end
end



def get_value(hash, key)
  if hash.key?(key.to_sym)
    hash[key.to_sym]
  elsif hash.key?(key.to_s)
    hash[key.to_s]
  end
end



def create_request_handler(routes)
  raise ArgumentError, 'A routes object is required' unless routes.is_a?(Hash)

  my_routes = {}

  routes.each do |key, route|
    route_error = validate_route(key, false)
    raise ArgumentError, "#{route_error}: #{key}" if route_error

    if route.is_a?(Array)
      raise ArgumentError, "Route has no handlers: #{key}" if route.empty?

      route.each do |handler|
        raise ArgumentError, "All route handlers must be functions: #{key}" unless handler.is_a?(Proc)
      end

      my_routes[key] = { handler: route }
    elsif route.is_a?(Hash)
      unless route.key?(:handler)
        raise ArgumentError, "Route has no handlers: #{key}"
      end

      if route[:handler].is_a?(Array)
        route[:handler].each do |handler|
          raise ArgumentError, "All route handlers must be functions: #{key}" unless handler.is_a?(Proc)
        end

        my_routes[key] = route
      elsif route[:handler].is_a?(Proc)
        my_routes[key] = { **route, handler: [route[:handler]] }
      else
        raise ArgumentError, "Route handler is not valid: #{key}"
      end
    elsif route.is_a?(Proc)
      my_routes[key] = { handler: [route] }
    else
      raise ArgumentError, "Route is missing handler: #{key}"
    end
  end

  handler = lambda do |requests, context = {}|
    handle_request(my_routes, requests, context)
  end

  return handler
end



def validate_route(route, system)
  route_regex = /^[a-zA-Z][a-zA-Z0-9_\-\/]*[a-zA-Z0-9]$/
  system_route_regex = /^_[a-zA-Z][a-zA-Z0-9_\-\/]*[a-zA-Z0-9]$/
  if route.nil? || route.empty?
    return 'Route is required'
  elsif system && !(route =~ system_route_regex)
    route_length = route.length
    if route_length < 3
      return 'System route should be at least three characters long'
    elsif route[0] != '_'
      return 'System route should start with an underscore'
    elsif !(route[-1] =~ /^[a-zA-Z0-9]/)
      return 'System route should end with a letter or a number'
    else
      return 'System route should contain only letters, numbers, dashes, underscores, and forward slashes'
    end
  elsif !system && !(route =~ route_regex)
    route_length = route.length
    if route_length < 2
      return 'Route should be at least two characters long'
    elsif !(route[0] =~ /^[a-zA-Z]/)
      return 'Route should start with a letter'
    elsif !(route[-1] =~ /^[a-zA-Z0-9]/)
      return 'Route should end with a letter or a number'
    else
      return 'Route should contain only letters, numbers, dashes, underscores, and forward slashes'
    end
  elsif route =~ /\/[^a-zA-Z]/
    return 'Sub-routes should start with a letter'
  elsif route =~ /[^a-zA-Z0-9]\//
    return 'Sub-routes should end with a letter or a number'
  elsif route =~ /\/[a-zA-Z0-9_\-]{0,1}\//
    return 'Sub-routes should be at least two characters long'
  elsif route =~ /\/[a-zA-Z0-9_\-]$/
    return 'Sub-routes should be at least two characters long'
  elsif route =~ /^[a-zA-Z0-9_\-]\//
    return 'Sub-routes should be at least two characters long'
  end

  return nil
end



def handle_request(routes, requests, context = {})
  if requests.nil? || !requests.is_a?(Array)
    return handle_error(400, 'Request should be an array')
  end

  batch_id = SecureRandom.uuid()
  unique_ids = []
  promises = []

  requests.each do |request|
    request_length = request.length
    if !request.is_a?(Array)
      return handle_error(400, 'Request item should be an array')
    end

    id = request[0] || nil
    route = request[1] || nil
    body = request[2] || nil
    headers = request[3] || nil

    if id.nil? || !id.is_a?(String)
      return handle_error(400, 'Request item should have an ID')
    end

    if route.nil? || !route.is_a?(String)
      return handle_error(400, 'Request items should have a route')
    end

    if body && !body.is_a?(Hash)
      return handle_error(400, 'Request item body should be an object')
    end

    if headers && !headers.is_a?(Hash)
      return handle_error(400, 'Request item headers should be an object')
    end

    if unique_ids.include?(id)
      return handle_error(400, 'Request items should have unique IDs')
    end

    unique_ids << id
    this_route = routes[route]
    route_handler = nil
    timeout = nil

    if this_route.is_a?(Hash)
      route_handler = this_route[:handler] || this_route['handler'] || method(:route_not_found)
      timeout = this_route[:timeout] || this_route['timeout'] || nil
    else
      route_handler = this_route || method(:route_not_found)
    end

    request_object = {
      id: id,
      route: route,
      body: body || {},
      headers: headers
    }

    request_context = {}
    if context.is_a?(Hash)
      request_context = request_context.merge(context)
    end
    request_context["batch_id"] = batch_id
    request_context["request_id"] = id
    request_context["route"] = route
    request_context["headers"] = headers

    promises << Thread.new { route_reducer(route_handler, request_object, request_context, timeout) }
  end

  results = promises.map(&:value)
  return handle_result(results)
end



def handle_result(result)
  return result, nil
end



def handle_error(status, message)
  return nil, {
    'status' => status,
    'message' => message
  }
end



class BlestError < StandardError
  attr_accessor :status
  attr_accessor :code
  attr_accessor :data
  attr_accessor :stack

  def initialize(message = nil)
    @status = 500
    @code = nil
    @data = nil
    @stack = nil
    super(message)
  end
end



def route_not_found(_, _)
  error = BlestError.new
  error.status = 404
  error.stack = nil
  raise error, 'Not Found'
end



def route_reducer(handler, request, context, timeout = nil)
  safe_context = Marshal.load(Marshal.dump(context))
  route = request[:route]
  result = nil
  error = nil

  target = -> do
    my_result = nil
    if handler.is_a?(Array)
      handler.each do |h|
        break if error
        temp_result = nil
        if h.respond_to?(:call)
          temp_result = Concurrent::Promises.future do
            begin
              h.call(request[:body], safe_context)
            rescue => e
              error = e
            end
          end.value
        else
          puts "Tried to resolve route '#{route}' with handler of type '#{h.class}'"
          raise StandardError
        end

        if temp_result && temp_result != nil
          if my_result && my_result != nil
            puts result
            puts temp_result
            puts "Multiple handlers on the route '#{route}' returned results"
            raise StandardError
          else
            my_result = temp_result
          end
        end
      end
    else
      if handler.respond_to?(:call)
        my_result = Concurrent::Promises.future do
          begin
            handler.call(request[:body], safe_context)
          rescue => e
            error = e
          end
        end.value
      else
        puts "Tried to resolve route '#{route}' with handler of type '#{handler.class}'"
        raise StandardError
      end
    end

    if error
      raise error
    end

    my_result
  end

  begin
    if timeout && timeout > 0
      begin
        result = Timeout.timeout(timeout / 1000.0) { target.call }
      rescue Timeout::Error
        puts "The route '#{route}' timed out after #{timeout} milliseconds"
        return [request[:id], request[:route], nil, { 'message' => 'Internal Server Error', 'status' => 500 }]
      end
    else
      result = target.call
    end

    if result.nil? || !result.is_a?(Hash)
      puts "The route '#{route}' did not return a result object"
      return [request[:id], request[:route], nil, { 'message' => 'Internal Server Error', 'status' => 500 }]
    end

    # if request[:selector]
    if request&.headers&._s
      result = filter_object(result, request.headers._s)
    end

    [request[:id], request[:route], result, nil]
  rescue => error
    puts error.backtrace
    response_error = {
      'message' => error.message || 'Internal Server Error',
      'status' => error.respond_to?(:status) ? error.status : 500
    }

    if error.respond_to?(:code) && error.code.is_a?(String)
      response_error['code'] = error.code
    end

    if error.respond_to?(:data) && error.data.is_a?(Hash)
      response_error['data'] = error.data
    end

    if ENV['ENVIRONMENT'] != 'production' && ENV['APP_ENV'] != 'production' && ENV['RACK_ENV'] != 'production' && ENV['RAILS_ENV'] != 'production' && !error.respond_to?(:stack)
      response_error['stack'] = error.backtrace
    end

    [request[:id], request[:route], nil, response_error]
  end
end



def filter_object(obj, arr)
  if arr.is_a?(Array)
    filtered_obj = {}
    arr.each do |key|
      if key.is_a?(String)
        if obj.key?(key.to_sym)
          filtered_obj[key.to_sym] = obj[key.to_sym]
        end
      elsif key.is_a?(Array)
        nested_obj = obj[key[0].to_sym]
        nested_arr = key[1]
        if nested_obj.is_a?(Array)
          filtered_arr = []
          nested_obj.each do |nested_item|
            filtered_nested_obj = filter_object(nested_item, nested_arr)
            if filtered_nested_obj.keys.length > 0
              filtered_arr << filtered_nested_obj
            end
          end
          if filtered_arr.length > 0
            filtered_obj[key[0].to_sym] = filtered_arr
          end
        elsif nested_obj.is_a?(Hash)
          filtered_nested_obj = filter_object(nested_obj, nested_arr)
          if filtered_nested_obj.keys.length > 0
            filtered_obj[key[0].to_sym] = filtered_nested_obj
          end
        end
      end
    end
    return filtered_obj
  end
  return obj
end