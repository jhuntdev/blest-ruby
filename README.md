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

## Installation

Install BLEST Ruby from Rubygems.

```bash
gem install blest
```

## Usage

Use the `create_request_handler` function to create a request handler suitable for use in an existing Python application. Use the `create_http_server` function to create a standalone HTTP server for your request handler.

<!-- Use the `create_http_client` function to create a BLEST HTTP client. -->

### create_request_handler

```ruby
require 'webrick'
require 'json'
require 'blest'

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

class HttpRequestHandler < WEBrick::HTTPServlet::AbstractServlet
  def do_OPTIONS(request, response)
    response.status = 200
    response['Access-Control-Allow-Origin'] = '*'
    response['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
    response['Access-Control-Allow-Headers'] = 'Content-Type'
  end

  def do_POST(request, response)
    response['Content-Type'] = 'application/json'
    response['Access-Control-Allow-Origin'] = '*'

    # Parse JSON body
    begin
      payload = JSON.parse(request.body)
      
      # Define the request context
      context = {
        headers: request.headers
      }

      # Use the request handler
      result, error = handler.(payload, context)

      # Do something with the result or error
      if error
        response_body = error.to_json
        response.status = 500
        response.body = response_body
      elsif result
        response_body = result.to_json
        response.status = 200
        response.body = response_body
      else
        response.status = 204
      end

    rescue JSON::ParserError
      response.status = 400
      response.body = { message: 'Invalid JSON' }.to_json
    end
  end
end

# Create WEBrick server
server = WEBrick::HTTPServer.new(Port: 8000)

# Mount custom request handler
server.mount('/', HttpRequestHandler)

trap('INT') { server.shutdown }

# Start the server
server.start
```

### create_http_server

```ruby
require 'blest'

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