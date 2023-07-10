# BLEST Ruby

The Ruby reference implementation of BLEST (Batch-able, Lightweight, Encrypted State Transfer), an improved communication protocol for web APIs which leverages JSON, supports request batching and selective returns, and provides a modern alternative to REST.

To learn more about BLEST, please refer to the white paper: https://jhunt.dev/BLEST%20White%20Paper.pdf

For a front-end implementation in React, please visit https://github.com/jhuntdev/blest-react

## Features

- Built on JSON - Reduce parsing time and overhead
- Request Batching - Save bandwidth and reduce load times
- Compact Payloads - Save more bandwidth
- Selective Returns - Save even more bandwidth
- Single Endpoint - Reduce complexity and improve data privacy
- Fully Encrypted - Improve data privacy

<!-- ## Installation

Install BLEST Python from PyPI.

```bash
python3 -m pip install blest
``` -->

## Usage

Use the `create_request_handler` function to create a request handler suitable for use in an existing Python application. Use the `create_http_server` function to create a standalone HTTP server for your request handler.

<!-- Use the `create_http_client` function to create a BLEST HTTP client. -->

### create_request_handler

```ruby
require 'socket'
require 'json'
require './blest.rb'

server = TCPServer.new('localhost', 8080)

# Create some middleware (optional)
auth_middleware = ->(params, context) {
  if params[:name].present?
    context[:user] = {
      name: params[:name]
    }
    nil
  else
    raise RuntimeError, "Unauthorized"
  end
}

# Create a route controller
greet_controller = ->(params, context) {
  {
    greeting: "Hi, #{context[:user][:name]}!"
  }
}

# Create a router
router = {
  greet: [auth_middleware, greet_controller]
}

# Create a request handler
handler = create_request_handler(router)

puts "Server listening on port 8080"

loop do

  client = server.accept

  request = client.gets
  if request.nil?
    client.close
  else

    method, path, _ = request.split(' ')

    if method != 'POST' 
      client.puts "HTTP/1.1 405 Method Not Allowed"
      client.puts "\r\n"
    elsif path != '/'
      client.puts "HTTP/1.1 404 Not Found"
      client.puts "\r\n"
    else
      content_length = 0
      while line = client.gets
        break if line == "\r\n"
        content_length = line.split(': ')[1].to_i if line.start_with?('Content-Length')
      end

      body = client.read(content_length)
      data = JSON.parse(body)

      context = {
        headers: request.headers
      }

      # Use the request handler]
      result, error = handler.(data, context)

      if error
          response = error.to_json
          client.puts "HTTP/1.1 500 Internal Server Error"
          client.puts "Content-Type: application/json"
          client.puts "Content-Length: #{response.bytesize}"
          client.puts "\r\n"
          client.puts response
      elsif result
          response = result.to_json
          client.puts "HTTP/1.1 200 OK"
          client.puts "Content-Type: application/json"
          client.puts "Content-Length: #{response.bytesize}"
          client.puts "\r\n"
          client.puts response
      else
          client.puts "HTTP/1.1 204 No Content"
      end
    end

    client.close

  end
end
```

### create_http_server

```ruby
require 'socket'
require 'json'
require './blest.rb'

# Create some middleware (optional)
auth_middleware = ->(params, context) {
  if params[:name].present?
    context[:user] = {
      name: params[:name]
    }
    nil
  else
    raise RuntimeError, "Unauthorized"
  end
}

# Create a route controller
greet_controller = ->(params, context) {
  {
    greeting: "Hi, #{context[:user][:name]}!"
  }
}

# Create a router
router = {
  greet: [auth_middleware, greet_controller]
}

# Create a request handler
handler = create_request_handler(router)

# Create the server
server = create_http_server(handler, { port: 8080 })

# Run the server
server.()
```

## License

This project is licensed under the [MIT License](LICENSE).