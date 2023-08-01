require 'sinatra'
require 'json'
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

before do
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'POST, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type'
end

options '*' do
  200
end

post '/' do
  json_body = JSON.parse(request.body.read)
  headers = env.select { |k, _| k.start_with?('HTTP_') }
                .collect { |k, v| [k.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-'), v] }
                .to_h
  
  result, error = router.handle(json_body, { 'headers' => headers })

  content_type :json
  if error
    raise Sinatra::Error.new(error.status || 500, error)
  else
    result
  end
end
