require 'json'
require 'rack/cors'
require 'blest'

router = Router.new()

router.route('hello') do |params, context|
  {
    'hello': 'world',
    'bonjour': 'le monde',
    'hola': 'mundo',
    'hallo': 'welt'
  }
end

router.route('greet') do |params, context|
  {
    'greeting': 'Hi, ' + params.get('name') + '!'
  }
end

router.route('fail') do |params, context|
  raise StandardError('Intentional failure')
end

module Api
  class Application < Hanami::API
    use Rack::Cors do
      allow do
        origins '*'
        resource '*', headers: :any, methods: [:post, :options]
      end
    end

    post '/' do
      begin
        json_body = JSON.parse(request.body.read)
      rescue JSON::ParserError
        error!('Invalid JSON', 400)
      end

      result, err = router.handle(json_body, { 'headers' => request.env })

      if err
        error!(err.message, err.status || 500)
      else
        response.headers['Content-Type'] = 'application/json'
        result.to_json
      end
    end

    options '/' do
      response.headers['Access-Control-Allow-Origin'] = '*'
      response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
      response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
      response.status = 200
    end
  end
end
