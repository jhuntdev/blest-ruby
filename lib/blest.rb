require 'socket'
require 'json'

def create_http_server(request_handler, options = nil)
  
  def parse_request(request_line)
    method, path, _ = request_line.split(' ')
    { method: method, path: path }
  end

  def parse_headers(client)
    headers = {}

    while (line = client.gets.chomp)
      break if line.empty?

      key, value = line.split(':', 2)
      headers[key] = value.strip
    end

    headers
  end

  def parse_body(client, content_length)
    body = ''
  
    while content_length > 0
      chunk = client.readpartial([content_length, 4096].min)
      body += chunk
      content_length -= chunk.length
    end
  
    body
  end

  def build_response(status, headers, body)
    response = "HTTP/1.1 #{status}\r\n"
    headers.each { |key, value| response += "#{key}: #{value}\r\n" }
    response += "\r\n"
    response += body
    response
  end

  def handle_request(client, request_handler)
    request_line = client.gets
    return unless request_line
  
    request = parse_request(request_line)
    
    headers = parse_headers(client)
    
    cors_headers = {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'POST, OPTIONS',
      'Access-Control-Allow-Headers' => 'Content-Type'
    }
  
    if request[:path] != '/'
      response = build_response('404 Not Found', cors_headers, '')
      client.print(response)
    elsif request[:method] == 'OPTIONS'
      response = build_response('204 No Content', cors_headers, '')
      client.print(response)
    elsif request[:method] == 'POST'

      content_length = headers['Content-Length'].to_i
      body = parse_body(client, content_length)
      
      begin
        json_data = JSON.parse(body)
        context = {
          'headers' => headers
        }

        response_headers = cors_headers.merge({
          'Content-Type' => 'application/json'
        })

        result, error = request_handler.(json_data, context)

        if error
            response_json = error.to_json
            response = build_response('500 Internal Server Error', response_headers, response_json)
            client.print response
        elsif result
            response_json = result.to_json
            response = build_response('200 OK', response_headers, response_json)
            client.print response
        else
          response = build_response('500 Internal Server Error', response_headers, { 'message' => 'Request handler failed to return a result' }.to_json)
          client.print response
        end

      rescue JSON::ParserError
        response = build_response('400 Bad Request', cors_headers, '')
      end

    else
      response = build_response('405 Method Not Allowed', cors_headers, '')
      client.print(response)
    end
    client.close()
  end

  run = ->() do

    port = options&.fetch(:port, 8080) if options.is_a?(Hash)
    port ||= 8080

    server = TCPServer.new('localhost', 8080)
    puts "Server listening on port #{port}"

    loop do
      client = server.accept
      Thread.new { handle_request(client, request_handler) }
    end

  end

  return run
end

def create_request_handler(routes, options = nil)
  if options
    puts 'The "options" argument is not yet used, but may be used in the future'
  end

  def handle_result(result)
    return [result, nil]
  end

  def handle_error(code, message)
    return [nil, { 'code' => code, 'message' => message }]
  end

  def route_not_found(_, _)
    raise 'Route not found'
  end

  def route_reducer(handler, request, context = nil)
    safe_context = context ? context.clone : {}
    result = nil

    if handler.is_a?(Array)
      handler.each_with_index do |func, i|
        temp_result = func.call(request[:parameters], safe_context)

        if i == handler.length - 1
          result = temp_result
        else
          raise 'Middleware should not return anything but may mutate context' if temp_result
        end
      end
    else
      result = handler.call(request[:parameters], safe_context)
    end

    raise 'The result, if any, should be a JSON object' if result && !(result.is_a?(Hash))

    result = filter_object(result, request[:selector]) if result && request[:selector]
    return [request[:id], request[:route], result, nil]
  rescue StandardError => error
    return [request[:id], request[:route], nil, { message: error.message }]
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

  route_regex = /^[a-zA-Z][a-zA-Z0-9_\-\/]*[a-zA-Z0-9_\-]$/

  handler = ->(requests, context = {}) do
    if !requests || !requests.is_a?(Array)
      return handle_error(400, 'Request body should be a JSON array')
    end

    unique_ids = []
    promises = []

    requests.each do |request|
      if !request.is_a?(Array)
        return handle_error(400, 'Request item should be an array')
      end

      id = request[0]
      route = request[1]
      parameters = request[2] || nil
      selector = request[3] || nil

      if !id || !id.is_a?(String)
        return handle_error(400, 'Request item should have an ID')
      end

      if !route || !route.is_a?(String)
        return handle_error(400, 'Request item should have a route')
      end

      if !route_regex.match?(route)
        route_length = route.length
        if route_length < 2
          return handle_error(400, 'Request item route should be at least two characters long')
        elsif route[-1] == '/'
          return handle_error(400, 'Request item route should not end in a forward slash')
        elsif !/[a-zA-Z]/.match?(route[0])
          return handle_error(400, 'Request item route should start with a letter')
        else
          return handle_error(
            400,
            'Request item route should contain only letters, numbers, dashes, underscores, and forward slashes'
          )
        end
      end

      if parameters && !parameters.is_a?(Hash)
        return handle_error(400, 'Request item parameters should be a JSON object')
      end

      if selector && !selector.is_a?(Array)
        return handle_error(400, 'Request item selector should be a JSON array')
      end

      if unique_ids.include?(id)
        return handle_error(400, 'Request items should have unique IDs')
      end

      unique_ids << id

      route_handler = routes[route] || routes[route.to_sym] || method(:route_not_found)

      request_object = {
        id: id,
        route: route,
        parameters: parameters,
        selector: selector,
      }

      promises << route_reducer(route_handler, request_object, context)
    end

    results = []

    promises.each do |result|
      results << result
    end

    return handle_result(results)
  end

  return handler
end