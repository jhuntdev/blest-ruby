require 'bundler/setup'
require 'hanami/setup'
require_relative '../apps/api/application'

Hanami::Container.configure do
  mount Api::Application, at: '/'
end