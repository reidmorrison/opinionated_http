require "persistent_http"
require "secret_config"
require "semantic_logger"
#
# Client http implementation
#
# See README.md for more info.
module OpinionatedHTTP
  class Client
    # 502 Bad Gateway, 503 Service Unavailable, 504 Gateway Timeout
    HTTP_RETRY_CODES = %w[502 503 504].freeze

    attr_reader :secret_config_prefix, :logger, :metric_prefix, :error_class, :driver,
                :retry_count, :retry_interval, :retry_multiplier, :http_retry_codes,
                :url, :pool_size, :keep_alive, :proxy, :force_retry, :max_redirects,
                :open_timeout, :read_timeout, :idle_timeout, :pool_timeout, :warn_timeout

    # Any option supplied here can be overridden if that corresponding value is set in Secret Config.
    # Except for any values passed directly to Persistent HTTP under `**options`.
    def initialize(
      secret_config_prefix:,
      metric_prefix:,
      error_class:,
      logger: nil,
      retry_count: 11,
      retry_interval: 0.01,
      retry_multiplier: 1.8,
      http_retry_codes: HTTP_RETRY_CODES.join(","),
      url: nil,
      pool_size: 100,
      open_timeout: 10,
      read_timeout: 10,
      idle_timeout: 300,
      keep_alive: 300,
      pool_timeout: 5,
      warn_timeout: 0.25,
      proxy: :ENV,
      force_retry: true,
      max_redirects: 10,
      **options
    )
      @metric_prefix    = metric_prefix
      @logger           = logger || SemanticLogger[self]
      @error_class      = error_class
      @retry_count      = SecretConfig.fetch("#{secret_config_prefix}/retry_count", type: :integer, default: retry_count)
      @retry_interval   = SecretConfig.fetch("#{secret_config_prefix}/retry_interval", type: :float, default: retry_interval)
      @retry_multiplier = SecretConfig.fetch("#{secret_config_prefix}/retry_multiplier", type: :float, default: retry_multiplier)
      @max_redirects    = SecretConfig.fetch("#{secret_config_prefix}/max_redirects", type: :integer, default: max_redirects)
      http_retry_codes  = SecretConfig.fetch("#{secret_config_prefix}/http_retry_codes", type: :string, default: http_retry_codes)
      @http_retry_codes = http_retry_codes.split(",").collect(&:strip)

      @url = url.nil? ? SecretConfig["#{secret_config_prefix}/url"] : SecretConfig.fetch("#{secret_config_prefix}/url", default: url)

      @pool_size    = SecretConfig.fetch("#{secret_config_prefix}/pool_size", type: :integer, default: pool_size)
      @open_timeout = SecretConfig.fetch("#{secret_config_prefix}/open_timeout", type: :float, default: open_timeout)
      @read_timeout = SecretConfig.fetch("#{secret_config_prefix}/read_timeout", type: :float, default: read_timeout)
      @idle_timeout = SecretConfig.fetch("#{secret_config_prefix}/idle_timeout", type: :float, default: idle_timeout)
      @keep_alive   = SecretConfig.fetch("#{secret_config_prefix}/keep_alive", type: :float, default: keep_alive)
      @pool_timeout = SecretConfig.fetch("#{secret_config_prefix}/pool_timeout", type: :float, default: pool_timeout)
      @warn_timeout = SecretConfig.fetch("#{secret_config_prefix}/warn_timeout", type: :float, default: warn_timeout)
      @proxy        = SecretConfig.fetch("#{secret_config_prefix}/proxy", type: :symbol, default: proxy)
      @force_retry  = SecretConfig.fetch("#{secret_config_prefix}/force_retry", type: :boolean, default: force_retry)

      internal_logger = OpinionatedHTTP::Logger.new(@logger)
      new_options     = {
        logger:       internal_logger,
        debug_output: internal_logger,
        name:         "",
        pool_size:    @pool_size,
        open_timeout: @open_timeout,
        read_timeout: @read_timeout,
        idle_timeout: @idle_timeout,
        keep_alive:   @keep_alive,
        pool_timeout: @pool_timeout,
        warn_timeout: @warn_timeout,
        proxy:        @proxy,
        force_retry:  @force_retry
      }

      url               = SecretConfig["#{secret_config_prefix}/url"]
      new_options[:url] = url if url
      @driver           = PersistentHTTP.new(new_options.merge(options))
    end

    # Perform an HTTP Get against the supplied path
    def get(action:, path: "/#{action}", **args)
      request  = build_request(path: path, verb: "Get", **args)
      response = request(action: action, request: request)
      extract_body(response, 'GET', action)
    end

    def post(action:, path: "/#{action}", **args)
      request = build_request(path: path, verb: "Post", **args)

      response = request(action: action, request: request)
      extract_body(response, 'POST', action)
    end

    def build_request(verb:, path:, headers: nil, body: nil, form_data: nil, username: nil, password: nil, parameters: nil)
      unless headers_and_form_data_compatible?(headers, form_data)
        raise(ArgumentError, "Setting form data will overwrite supplied content-type")
      end
      raise(ArgumentError, "Cannot supply both form_data and a body") if body && form_data

      path = "/#{path}" unless path.start_with?("/")
      path = "#{path}?#{URI.encode_www_form(parameters)}" if parameters

      request = Net::HTTP.const_get(verb).new(path, headers)

      raise(ArgumentError, "#{request.class.name} does not support a request body") if body && !request.request_body_permitted?
      if parameters && !request.response_body_permitted?
        raise(ArgumentError, ":parameters cannot be supplied for #{request.class.name}")
      end

      request.body = body if body
      request.set_form_data form_data if form_data
      request.basic_auth(username, password) if username && password
      request
    end

    # Returns [HTTP Response] after submitting the request
    #
    # Notes:
    # - Does not raise an exception when the http response is not an HTTP OK (200.
    def request(action:, request:)
      request_with_retry(action: action, request: request)
    end

    private

    def request_with_retry(action:, request:, try_count: 0)
      http_method = request.method.upcase
      response    =
        begin
          payload = {}
          if logger.trace?
            payload[:parameters] = parameters
            payload[:path]       = request.path
          end
          message = "HTTP #{http_method}: #{action}" if logger.debug?

          logger.benchmark_info(message: message, metric: "#{metric_prefix}/#{action}", payload: payload) { driver.request(request) }
        rescue StandardError => e
          message = "HTTP #{http_method}: #{action} Failure: #{e.class.name}: #{e.message}"
          logger.error(message: message, metric: "#{metric_prefix}/exception", exception: e)
          raise(error_class, message)
        end

      # Retry on http 5xx errors except 500 which means internal server error.
      if http_retry_codes.include?(response.code)
        if try_count < retry_count
          try_count += 1
          duration = retry_sleep_interval(try_count)
          logger.warn(message: "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}. Retry: #{try_count}", metric: "#{metric_prefix}/retry", duration: duration * 1_000)
          sleep(duration)
          response = request_with_retry(action: action, request: request, try_count: try_count)
        else
          message = "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}. Retries Exhausted"
          logger.error(message: message, metric: "#{metric_prefix}/exception")
          raise(error_class, message)
        end
      end

      response
    end

    def extract_body(response, http_method, action)
      return response.body if response.is_a?(Net::HTTPSuccess)

      message = "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}"
      logger.error(message: message, metric: "#{metric_prefix}/exception")
      raise(error_class, message)
    end

    def prefix_path(path)
      path.start_with?("/") ? path : "/#{path}"
    end

    # First retry is immediate, next retry is after `retry_interval`,
    # each subsequent retry interval is 100% longer than the prior interval.
    def retry_sleep_interval(retry_count)
      return 0 if retry_count <= 1

      (retry_multiplier**(retry_count - 1)) * retry_interval
    end

    def headers_and_form_data_compatible?(headers, form_data)
      return true if headers.nil? || form_data.nil?

      !headers.keys.map(&:downcase).include?("content-type")
    end
  end
end
