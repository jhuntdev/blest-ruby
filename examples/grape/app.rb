require 'grape'
require 'json'
require 'blest'

router = Router.new()

router.route('hello') do |body, context|
  [
    { 'hello': 'world' },
    { 'bonjour': 'le monde' },
    { 'hola': 'mundo' },
    { 'hallo': 'welt' }
  ].sample
end

router.route('greet') do |body, context|
  {
    'greeting': 'Hi, ' + body.get('name') + '!'
  }
end

router.route('fail') do |body, context|
  raise StandardError('Intentional failure')
end

class MyAPI < Grape::API
  format :json

  use Rack::Cors do
    allow do
      origins '*'
      resource '*', headers: :any, methods: [:post, :options]
    end
  end

  options '/' do
    status 204
  end

  post '/' do
    headers = env.select { |k, _| k.start_with?('HTTP_') }
                  .collect { |k, v| [k.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-'), v] }
                  .to_h
    
    begin
      json_body = JSON.parse(request.body.read)
    rescue JSON::ParserError
      error!('Invalid JSON', 400)
    end

    result, error = router.handle(json_body, { 'httpHeaders' => headers })

    response_headers = {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*' # Allow all origins in the response headers
    }

    if error
      error_response(message: error.message, status: error.status || 500)
    else
      status 200
      headers response_headers
      body result.to_json
    end
  end
end