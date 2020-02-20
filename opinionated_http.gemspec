$:.push File.expand_path('lib', __dir__)

require 'opinionated_http/version'

Gem::Specification.new do |s|
  s.name        = 'opinionated_http'
  s.version     = OpinionatedHTTP::VERSION
  s.authors     = ['Reid Morrison']
  s.email       = ['reidmo@gmail.com']

  s.summary     = 'Opinionated HTTP Client'
  s.description = 'HTTP Client with retries. Uses PersistentHTTP for http connection pooling, Semantic Logger for logging and metrics, and uses Secret Config for its configuration.'

  s.files      = Dir['lib/**/*', 'Rakefile', 'README.md']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'persistent_http'
  s.add_dependency 'secret_config'
  s.add_dependency 'semantic_logger'
end
