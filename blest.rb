def create_request_handler(routes, options = nil)
    if options
      puts 'The "options" argument is not yet used, but may be used in the future'
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

        route_handler = routes[route.to_sym] || method(:route_not_found)
  
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
  

def handle_result(result)
  return [result, nil]
end

def handle_error(code, message)
  return [nil, { code: code, message: message }]
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
  puts error
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
