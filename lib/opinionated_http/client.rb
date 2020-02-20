require 'persistent_http'
require 'secret_config'
require 'semantic_logger'
#
# Client http implementation
#
module OpinionatedHTTP
  class Client
    attr_reader :secret_config_prefix, :logger, :metric_prefix, :error_class, :driver

    def initialize(secret_config_prefix:, logger: nil, metric_prefix:, error_class:, **options)
      @metric_prefix = metric_prefix
      @logger        = logger || SemanticLogger[self]
      @error_class   = error_class

      internal_logger = OpinionatedHTTP::Logger.new(@logger)
      new_options     = {
        logger:       internal_logger,
        debug_output: internal_logger,
        name:         "",
        pool_size:    SecretConfig.fetch("#{secret_config_prefix}/pool_size", type: :integer, default: 100),
        open_timeout: SecretConfig.fetch("#{secret_config_prefix}/open_timeout", type: :float, default: 10),
        read_timeout: SecretConfig.fetch("#{secret_config_prefix}/read_timeout", type: :float, default: 10),
        idle_timeout: SecretConfig.fetch("#{secret_config_prefix}/idle_timeout", type: :float, default: 300),
        keep_alive:   SecretConfig.fetch("#{secret_config_prefix}/keep_alive", type: :float, default: 300),
        pool_timeout: SecretConfig.fetch("#{secret_config_prefix}/pool_timeout", type: :float, default: 5),
        warn_timeout: SecretConfig.fetch("#{secret_config_prefix}/warn_timeout", type: :float, default: 0.25),
        proxy:        SecretConfig.fetch("#{secret_config_prefix}/proxy", type: :symbol, default: :ENV),
        force_retry:  SecretConfig.fetch("#{secret_config_prefix}/force_retry", type: :boolean, default: true),
      }

      url               = SecretConfig["#{secret_config_prefix}/url"]
      new_options[:url] = url if url
      @driver           = PersistentHTTP.new(new_options.merge(options))
    end

    # Perform an HTTP Get against the supplied path
    def get(action:, path: "/#{action}", parameters: nil)
      path = "/#{path}" unless path.start_with?("/")
      path = "#{path}?#{URI.encode_www_form(parameters)}" if parameters

      request  = Net::HTTP::Get.new(path)
      response =
        begin
          payload = {}
          if logger.trace?
            payload[:parameters] = parameters
            payload[:path]       = path
          end
          message = "HTTP GET: #{action}" if logger.debug?

          logger.benchmark_info(message: message, metric: "#{metric_prefix}/#{action}", payload: payload) { driver.request(request) }
        rescue StandardError => exc
          message = "HTTP GET: #{action} Failure: #{exc.class.name}: #{exc.message}"
          logger.error(message: message, metric: "#{metric_prefix}/exception", exception: exc)
          raise(error_class, message)
        end

      unless response.is_a?(Net::HTTPSuccess)
        message = "HTTP GET: #{action} Failure: (#{response.code}) #{response.message}"
        logger.error(message: message, metric: "#{metric_prefix}/exception")
        raise(error_class, message)
      end

      response.body
    end

    def post(action:, path: "/#{action}", parameters: nil)
      path    = "/#{path}" unless path.start_with?("/")
      request = Net::HTTP::Post.new(path)
      request.set_form_data(*parameters) if parameters

      response =
        begin
          payload = {}
          if logger.trace?
            payload[:parameters] = parameters
            payload[:path]       = path
          end
          message = "HTTP POST: #{action}" if logger.debug?

          logger.benchmark_info(message: message, metric: "#{metric_prefix}/#{action}", payload: payload) { driver.request(request) }
        rescue StandardError => exc
          message = "HTTP POST: #{action} Failure: #{exc.class.name}: #{exc.message}"
          logger.error(message: message, metric: "#{metric_prefix}/exception", exception: exc)
          raise(error_class, message)
        end

      unless response.is_a?(Net::HTTPSuccess)
        message = "HTTP POST: #{action} Failure: (#{response.code}) #{response.message}"
        logger.error(message: message, metric: "#{metric_prefix}/exception")
        raise(error_class, message)
      end

      response.body
    end
  end
end
