$LOAD_PATH.unshift File.dirname(__FILE__) + "/../lib"
ENV["TZ"] = "America/New_York"

require "yaml"
require "minitest/autorun"
require "awesome_print"
require "secret_config"
require "semantic_logger"
require "opinionated_http"

SemanticLogger.add_appender(file_name: "test.log", formatter: :color)
SemanticLogger.default_level = :debug

SecretConfig.use :file, path: "test", file_name: File.expand_path("config/application.yml", __dir__)
