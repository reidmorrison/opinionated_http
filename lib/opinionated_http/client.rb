require 'persistent_http'
require 'secret_config'
require 'semantic_logger'
#
# Client http implementation
#
# See README.md for more info.
module OpinionatedHTTP
  class Client
    # 502 Bad Gateway, 503 Service Unavailable, 504 Gateway Timeout
    HTTP_RETRY_CODES = %w[502 503 504]

    attr_reader :secret_config_prefix, :logger, :metric_prefix, :error_class, :driver,
                :retry_count, :retry_interval, :retry_multiplier, :http_retry_codes

    def initialize(secret_config_prefix:, logger: nil, metric_prefix:, error_class:, **options)
      @metric_prefix    = metric_prefix
      @logger           = logger || SemanticLogger[self]
      @error_class      = error_class
      @retry_count      = SecretConfig.fetch("#{secret_config_prefix}/retry_count", type: :integer, default: 11)
      @retry_interval   = SecretConfig.fetch("#{secret_config_prefix}/retry_interval", type: :float, default: 0.01)
      @retry_multiplier = SecretConfig.fetch("#{secret_config_prefix}/retry_multiplier", type: :float, default: 1.8)
      http_retry_codes  = SecretConfig.fetch("#{secret_config_prefix}/http_retry_codes", type: :string, default: HTTP_RETRY_CODES.join(","))
      @http_retry_codes = http_retry_codes.split(",").collect { |str| str.strip }

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
      response = request_with_retry(action: action, path: path, request: request)

      response.body
    end

    def post(action:, path: "/#{action}", parameters: nil)
      path    = "/#{path}" unless path.start_with?("/")
      request = Net::HTTP::Post.new(path)
      request.set_form_data(*parameters) if parameters

      response = request_with_retry(action: action, path: path, request: request)

      response.body
    end

    private

    def request_with_retry(action:, path: "/#{action}", request:, try_count: 0)
      http_method = request.method.upcase
      response    =
        begin
          payload = {}
          if logger.trace?
            payload[:parameters] = parameters
            payload[:path]       = path
          end
          message = "HTTP #{http_method}: #{action}" if logger.debug?

          logger.benchmark_info(message: message, metric: "#{metric_prefix}/#{action}", payload: payload) { driver.request(request) }
        rescue StandardError => exc
          message = "HTTP #{http_method}: #{action} Failure: #{exc.class.name}: #{exc.message}"
          logger.error(message: message, metric: "#{metric_prefix}/exception", exception: exc)
          raise(error_class, message)
        end

      # Retry on http 5xx errors except 500 which means internal server error.
      if http_retry_codes.include?(response.code)
        if try_count < retry_count
          try_count = try_count + 1
          duration  = retry_sleep_interval(try_count)
          logger.warn(message: "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}. Retry: #{try_count}", metric: "#{metric_prefix}/retry", duration: duration * 1_000)
          sleep(duration)
          response = request_with_retry(action: action, path: path, request: request, try_count: try_count)
        else
          message = "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}. Retries Exhausted"
          logger.error(message: message, metric: "#{metric_prefix}/exception")
          raise(error_class, message)
        end
      elsif !response.is_a?(Net::HTTPSuccess)
        message = "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}"
        logger.error(message: message, metric: "#{metric_prefix}/exception")
        raise(error_class, message)
      end

      response
    end

    # First retry is immediate, next retry is after `retry_interval`,
    # each subsequent retry interval is 100% longer than the prior interval.
    def retry_sleep_interval(retry_count)
      return 0 if retry_count <= 1
      (retry_multiplier ** (retry_count - 1)) * retry_interval
    end
  end
end
