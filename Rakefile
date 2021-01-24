# Setup bundler to avoid having to run bundle exec all the time.
require "rubygems"
require "bundler/setup"

require "rake/testtask"
require_relative "lib/opinionated_http/version"

task :gem do
  system "gem build opinionated_http.gemspec"
end

task publish: :gem do
  system "git tag -a v#{OpinionatedHTTP::VERSION} -m 'Tagging #{OpinionatedHTTP::VERSION}'"
  system "git push --tags"
  system "gem push opinionated_http-#{OpinionatedHTTP::VERSION}.gem"
  system "rm opinionated_http-#{OpinionatedHTTP::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = false
end

task default: :test
