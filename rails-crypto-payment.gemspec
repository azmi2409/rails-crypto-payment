Gem::Specification.new do |spec|
  spec.name = "rails-crypto-payment"
  spec.version = "0.1.0"
  spec.authors = ["Azmi"]
  spec.summary = "Exact crypto amounts and exchange/chain deposit clients"
  spec.description = "Framework-independent USDT amount reservation and deposit retrieval for Rails payment integrations."
  spec.homepage = "https://github.com/azmi2409/rails-crypto-payment"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]
  spec.add_dependency "bigdecimal"
  spec.add_development_dependency "minitest", "~> 5.0"
end
