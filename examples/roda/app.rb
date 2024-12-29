require 'roda'
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

class MyApp < Roda
  plugin :json
  plugin :halt
  plugin :all_verbs
  plugin :request_headers

  route do |r|
    response['Access-Control-Allow-Origin'] = '*'
    response['Access-Control-Allow-Headers'] = 'Content-Type'
    response['Access-Control-Allow-Methods'] = 'POST, OPTIONS'

    r.options do
      response.status = 200
      ''
    end

    r.post do
      if r.content_type =~ /\Aapplication\/json/
        begin
          json_body = JSON.parse(r.body.read)
        rescue JSON::ParserError
          response.status = 400
          next { error: 'Invalid JSON data' }
        end

        result, error = router.handle(json_body, { 'httpHeaders' => r.httpHeaders })
        
        if error
          response.status = error.status || 500
          next { error: error.message }
        else
          result
        end
      else
        response.status = 415
        { error: 'Unsupported Media Type. Content-Type should be application/json.' }
      end
    end
  end
end