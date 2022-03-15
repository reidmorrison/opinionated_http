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

    attr_reader :secret_config_prefix, :logger, :format, :metric_prefix, :error_class, :driver, :format,
                :retry_count, :retry_interval, :retry_multiplier, :http_retry_codes,
                :url, :pool_size, :keep_alive, :proxy, :force_retry, :max_redirects,
                :open_timeout, :read_timeout, :idle_timeout, :pool_timeout, :warn_timeout,
                :after_connect

    # Any option supplied here can be overridden if that corresponding value is set in Secret Config.
    def initialize(
      secret_config_prefix:,
      metric_prefix:,
      error_class:,
      logger: nil,
      format: nil,
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
      after_connect: nil,
      verify_peer: false, # TODO: PersistentHTTP keeps returning cert expired even when it is valid.
      certificate: nil,
      private_key: nil,
      header: nil
    )
      @metric_prefix = metric_prefix
      @logger        = logger || SemanticLogger[self]
      @error_class   = error_class
      @format        = format
      @after_connect = after_connect
      SecretConfig.configure(secret_config_prefix) do |config|
        @retry_count      = config.fetch("retry_count", type: :integer, default: retry_count)
        @retry_interval   = config.fetch("retry_interval", type: :float, default: retry_interval)
        @retry_multiplier = config.fetch("retry_multiplier", type: :float, default: retry_multiplier)
        @max_redirects    = config.fetch("max_redirects", type: :integer, default: max_redirects)
        http_retry_codes  = config.fetch("http_retry_codes", type: :string, default: http_retry_codes)
        @http_retry_codes = http_retry_codes.split(",").collect(&:strip)

        @url = url.nil? ? config.fetch("url") : config.fetch("url", default: url)

        @pool_size    = config.fetch("pool_size", type: :integer, default: pool_size)
        @open_timeout = config.fetch("open_timeout", type: :float, default: open_timeout)
        @read_timeout = config.fetch("read_timeout", type: :float, default: read_timeout)
        @idle_timeout = config.fetch("idle_timeout", type: :float, default: idle_timeout)
        @keep_alive   = config.fetch("keep_alive", type: :float, default: keep_alive)
        @pool_timeout = config.fetch("pool_timeout", type: :float, default: pool_timeout)
        @warn_timeout = config.fetch("warn_timeout", type: :float, default: warn_timeout)
        @proxy        = config.fetch("proxy", type: :symbol, default: proxy)
        @force_retry  = config.fetch("force_retry", type: :boolean, default: force_retry)
        @certificate  = config.fetch("certificate", type: :string, default: certificate)
        @private_key  = config.fetch("private_key", type: :string, default: private_key)
        @verify_peer  = config.fetch("verify_peer", type: :boolean, default: verify_peer)
      end

      internal_logger = OpinionatedHTTP::Logger.new(@logger)
      @driver         = PersistentHTTP.new(
        url:           @url,
        logger:        internal_logger,
        debug_output:  internal_logger,
        name:          "",
        pool_size:     @pool_size,
        open_timeout:  @open_timeout,
        read_timeout:  @read_timeout,
        idle_timeout:  @idle_timeout,
        keep_alive:    @keep_alive,
        pool_timeout:  @pool_timeout,
        warn_timeout:  @warn_timeout,
        proxy:         @proxy,
        force_retry:   @force_retry,
        after_connect: @after_connect,
        certificate:   @certificate,
        private_key:   @private_key,
        verify_mode:   @verify_peer ? OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT : OpenSSL::SSL::VERIFY_NONE,
        header:        header
      )
    end

    def get(request: nil, **args)
      request       ||= Request.new(**args)
      request.verb  = "Get"
      http_response = request(request)
      Response.new(http_response, request)
    end

    def post(request: nil, json: nil, body: nil, **args)
      raise(ArgumentError, "Either set :json or :body") if json && body

      request       ||= Request.new(**args)
      if json
        request.format = :json
        request.body   = json
      else
        request.body = body
      end
      request.verb  = "Post"
      http_response = request(request)
      Response.new(http_response, request)
    end

    def delete(request: nil, **args)
      request       ||= Request.new(**args)
      request.verb  = "Delete"
      http_response = request(request)
      Response.new(http_response, request)
    end

    def patch(request: nil, **args)
      request       ||= Request.new(**args)
      request.verb  = "Patch"
      http_response = request(request)
      Response.new(http_response, request)
    end

    # Returns [Response] after submitting the [Request]
    def request(request)
      request.metric_prefix ||= metric_prefix
      request.format        ||= format
      request.error_class   ||= error_class
      request.logger        ||= logger
      request_with_retry(action: request.action, request: request.http_request)
    end

    private

    def request_with_retry(action:, request:, try_count: 0)
      http_method = request.method.upcase
      response    =
        begin
          payload = {}
          if logger.trace?
            # payload[:parameters] = parameters
            payload[:path] = request.path
          end
          message = "HTTP #{http_method}: #{action}" if logger.debug?

          logger.benchmark_info(message: message, metric: "#{metric_prefix}/#{action}", payload: payload) do
            driver.request(request)
          end
        rescue StandardError => e
          message = "HTTP #{http_method}: #{action} Failure: #{e.class.name}: #{e.message}"
          logger.error(message: message, metric: "#{metric_prefix}/exception", exception: e)
          raise(error_class, message)
        end

      # Retry on http 5xx errors except 500 which means internal server error.
      return response unless http_retry_codes.include?(response.code)

      if try_count >= retry_count
        message = "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}. Retries Exhausted"
        logger.error(message: message, metric: "#{metric_prefix}/exception")
        raise(error_class, message)
      end

      try_count += 1
      duration  = retry_sleep_interval(try_count)
      logger.warn(message: "HTTP #{http_method}: #{action} Failure: (#{response.code}) #{response.message}. Retry: #{try_count}", metric: "#{metric_prefix}/retry", duration: duration * 1_000)
      sleep(duration)
      request_with_retry(action: action, request: request, try_count: try_count)
    end

    # First retry is immediate, next retry is after `retry_interval`,
    # each subsequent retry interval is 100% longer than the prior interval.
    def retry_sleep_interval(retry_count)
      return 0 if retry_count <= 1

      (retry_multiplier ** (retry_count - 1)) * retry_interval
    end
  end
end
