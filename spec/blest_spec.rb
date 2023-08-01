require 'rspec'
require 'securerandom'
require_relative '../lib/blest'

RSpec.describe Router do

  benchmarks = []

  router =  Router.new(timeout: 1000)
  router2 =  Router.new(timeout: 10)
  router3 =  Router.new

  testId1 = nil
  testValue1 = nil
  result1 = nil
  error1 = nil
  testId2 =  nil
  testValue2 =  nil
  result2 =  nil
  error2 =  nil
  testId3 =  nil
  testValue3 =  nil
  result3 =  nil
  error3 =  nil
  testId4 =  nil
  testValue4 =  nil
  result4 = nil
  error4 = nil
  testId5 = nil
  testValue5 = nil
  result5 = nil
  error5 = nil
  testId6 = nil
  testValue6 = nil
  result6 = nil
  error6 = nil

  before(:all) do
    router.route('basicRoute') do |parameters, context|
      { 'route'=> 'basicRoute', 'parameters' => parameters, 'context' => context }
    end

    router.before do |parameters, context|
      context['test'] = { 'value' => parameters['testValue'] }
      nil
    end

    router.after do |_, context|
      complete_time = Time.now
      difference = (complete_time - context['requestTime'])
      benchmarks.push(difference)
      nil
    end

    router2.route('mergedRoute') do |parameters, context|
      { 'route' => 'mergedRoute', 'parameters' => parameters, 'context' => context }
    end

    router2.route('timeoutRoute') do |parameters|
      sleep(0.2)
      { 'testValue' => parameters['testValue'] }
    end

    router.merge(router2)

    router3.route('errorRoute') do |parameters|
      error = BlestError.new(parameters['testValue'])
      error.code = "ERROR_#{(parameters['testValue'].to_f * 10).round}"
      raise error
    end

    router.namespace('subRoutes', router3)

    # puts router.routes

    # Basic route
    testId1 = SecureRandom.uuid
    testValue1 = rand
    result1, error1 = router.handle([[testId1, 'basicRoute', { 'testValue' => testValue1 }]], { 'testValue' => testValue1 })

    # Merged route
    testId2 = SecureRandom.uuid
    testValue2 = rand
    result2, error2 = router.handle([[testId2, 'mergedRoute', { 'testValue' => testValue2 }]], { 'testValue' => testValue2 })

    # Error route
    testId3 = SecureRandom.uuid
    testValue3 = rand
    result3, error3 = router.handle([[testId3, 'subRoutes/errorRoute', { 'testValue' => testValue3 }]], { 'testValue' => testValue3 })

    # Missing route
    testId4 = SecureRandom.uuid
    testValue4 = rand
    result4, error4 = router.handle([[testId4, 'missingRoute', { 'testValue' => testValue4 }]], { 'testValue' => testValue4 })

    # Timeout route
    testId5 = SecureRandom.uuid
    testValue5 = rand
    result5, error5 = router.handle([[testId5, 'timeoutRoute', { 'testValue' => testValue5 }]], { 'testValue' => testValue5 })

    # Malformed request
    testId6 = SecureRandom.uuid
    result6, error6 = router.handle([[testId6], {}, [true, 1.25]])

  end

  it 'should have class properties' do
    expect(router.is_a?(Router)).to be_truthy
    expect(router.routes.keys.length).to eq(4)
    expect(router).to respond_to(:handle)
  end

  it 'should have class properties' do
    expect(router).to be_a(Router)
    expect(router.routes.keys.length).to eq(4)
    expect(router).to respond_to(:handle)
  end

  it 'should process all valid requests' do
    expect(error1).to be_nil
    expect(error2).to be_nil
    expect(error3).to be_nil
    expect(error4).to be_nil
    expect(error5).to be_nil
  end

  it 'should return matching IDs' do
    expect(result1[0][0]).to eq(testId1)
    expect(result2[0][0]).to eq(testId2)
    expect(result3[0][0]).to eq(testId3)
    expect(result4[0][0]).to eq(testId4)
    expect(result5[0][0]).to eq(testId5)
  end

  it 'should return matching routes' do
    expect(result1[0][1]).to eq('basicRoute')
    expect(result2[0][1]).to eq('mergedRoute')
    expect(result3[0][1]).to eq('subRoutes/errorRoute')
    expect(result4[0][1]).to eq('missingRoute')
    expect(result5[0][1]).to eq('timeoutRoute')
  end

  it 'should accept parameters' do
    expect(result1[0][2]['parameters']['testValue']).to eq(testValue1)
    expect(result2[0][2]['parameters']['testValue']).to eq(testValue2)
  end

  it 'should respect context' do
    expect(result1[0][2]['context']['testValue']).to eq(testValue1)
    expect(result2[0][2]['context']['testValue']).to eq(testValue2)
  end

  it 'should support middleware' do
    expect(result1[0][2]['context']['test']).to be_nil
    expect(result2[0][2]['context']['test']['value']).to eq(testValue2)
  end

  it 'should handle errors correctly' do
    expect(result1[0][3]).to be_nil
    expect(result2[0][3]).to be_nil
    expect(result3[0][3]['message']).to eq(testValue3.to_s)
    expect(result3[0][3]['status']).to eq(500)
    expect(result3[0][3]['code']).to eq("ERROR_#{(testValue3 * 10).round}")
    expect(result4[0][3]['message']).to eq('Not Found')
    expect(result4[0][3]['status']).to eq(404)
  end

  it 'should support timeout setting' do
    expect(result5[0][2]).to be_nil
    expect(result5[0][3]['message']).to eq('Internal Server Error')
    expect(result5[0][3]['status']).to eq(500)
  end

  it 'should reject malformed requests' do
    expect(error6['message']).not_to be_nil
  end

  it 'should allow trailing middleware' do
    expect(benchmarks.length).to eq(1)
  end

  it 'should throw an error for invalid routes' do
    handler = proc {}
    expect { router.route('a', &handler) }.to raise_error(ArgumentError)
    expect { router.route('0abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('_abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('-abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc_', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc-', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/0abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/_abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/-abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/', &handler) }.to raise_error(ArgumentError)
    expect { router.route('/abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc//abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/a/abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/0abc/abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/_abc/abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/-abc/abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/abc_/abc', &handler) }.to raise_error(ArgumentError)
    expect { router.route('abc/abc-/abc', &handler) }.to raise_error(ArgumentError)
  end

end



RSpec.describe HttpClient do
  client = HttpClient.new('http://localhost:8080', max_batch_size = 25, buffer_delay = 10)

  it 'should have class properties' do
    expect(client.is_a?(HttpClient)).to be_truthy
    expect(client.url).to eq('http://localhost:8080')
    expect(client.max_batch_size).to eq(25)
    expect(client.buffer_delay).to eq(10)
    expect(client).to respond_to(:request)
  end

end
