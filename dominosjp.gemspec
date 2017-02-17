require File.expand_path('../lib/version', __FILE__)

Gem::Specification.new do |s|
  s.name        = 'dominosjp'
  s.version     = DominosJP::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Mahdi Bchetnia']
  s.email       = ['injekter@gmail.com'] # Real email is on my website ;)
  s.homepage    = 'https://github.com/inket/dominosjp'
  s.summary     = 'Order Domino\'s Pizza Japan via CLI 🍕'
  s.description = 'A ruby gem for ordering Domino\'s Pizza in Japan via CLI 🍕'

  s.required_rubygems_version = '>= 1.3.6'
  s.rubyforge_project         = 'dominosjp'
  s.files                     = Dir['{lib}/**/*.rb', 'bin/*', 'LICENSE', '*.md']
  s.require_path              = 'lib'
  s.executables               = ['dominosjp']
  s.license                   = 'MIT'

  s.add_runtime_dependency 'colorize', '~> 0.8'
  s.add_runtime_dependency 'credit_card_validations', '~> 3.4'
  s.add_runtime_dependency 'highline', '~> 1.7'
  s.add_runtime_dependency 'http-cookie', '~> 1.0'
  s.add_runtime_dependency 'inquirer', '~> 0.2'
  s.add_runtime_dependency 'nokogiri', '~> 1.7'
end
