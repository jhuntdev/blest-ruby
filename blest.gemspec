# frozen_string_literal: true

Gem::Specification.new do |spec|
    spec.name          = "blest"
    spec.version       = "0.0.2"
    spec.authors       = ["JHunt"]
    spec.email         = ["blest@jhunt.dev"]
    spec.summary       = %q{The Ruby reference implementation of BLEST}
    spec.description   = %q{The Ruby reference implementation of BLEST (Batch-able, Lightweight, Encrypted State Transfer), an improved communication protocol for web APIs which leverages JSON, supports request batching and selective returns, and provides a modern alternative to REST.}
    spec.homepage      = "https://blest.jhunt.dev"
    spec.license       = "MIT"
  
    spec.files         = Dir["{lib,spec}/**/*", "README.md", "LICENSE"]
    spec.require_paths = ["lib"]
end