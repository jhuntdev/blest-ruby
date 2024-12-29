# BLEST Ruby

The Ruby reference implementation of BLEST (Batch-able, Lightweight, Encrypted State Transfer), an improved communication protocol for web APIs which leverages JSON, supports request batching by default, and provides a modern alternative to REST.

To learn more about BLEST, please visit the website: https://blest.jhunt.dev

For a front-end implementation in React, please visit https://github.com/jhuntdev/blest-react

## Features

- Built on JSON - Reduce parsing time and overhead
- Request Batching - Save bandwidth and reduce load times
- Compact Payloads - Save even more bandwidth
- Single Endpoint - Reduce complexity and facilitate introspection
- Fully Encrypted - Improve data privacy

## Installation

Install BLEST Ruby from Rubygems.

```bash
gem install blest
```

## Usage

### Router

The following example uses Sinatra, but you can find examples with other frameworks [here](examples).

```ruby
require 'sinatra'
require 'json'
require 'blest'

# Instantiate the Router
router = Router.new(timeout: 1000)

# Create some middleware (optional)
router.before do |body, context|
  context['user'] = {
    # user info for example
  }
end

# Create a route controller
router.route('greet') do |body, context|
  {
    greeting: "Hi, #{body['name']}!"
  }
end

# Handle BLEST requests
post '/' do
  json_body = JSON.parse(request.body.read)
  headers = request.env.select { |k, _| k.start_with?('HTTP_') }
  result, error = router.handle.call(json_body, { 'headers' => headers })
  content_type :json
  if error
    raise Sinatra::Error.new(error.status || 500, error)
  else
    result
  end
end
```

### HttpClient

```ruby
require 'blest'

# Create a client
client = HttpClient.new('http://localhost:8080', max_batch_size = 25, buffer_delay = 10, http_headers = {
  'Authorization': 'Bearer token'
})

# Send a request
begin
  result = client.request('greet', { 'name': 'Steve' }).value
  # Do something with the result
rescue => error
  # Do something in case of error
end
```


## License

This project is licensed under the [MIT License](LICENSE).