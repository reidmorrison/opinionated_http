require "forwardable"
module OpinionatedHTTP
  # The response object
  class Response
    extend Forwardable

    def_instance_delegators :@http_response, :code, :message
    def_instance_delegators :@request, :verb, :action, :metric_prefix, :format, :path, :error_class, :logger

    # :action used for logging the action in the error message
    def initialize(http_response, request)
      @http_response = http_response
      @request       = request
    end

    def success?
      @http_response.is_a?(Net::HTTPSuccess)
    end

    def body
      @body ||= parse_body
    end

    # Raises an exception when the HTTP Response is not a success
    def body!
      return body if success?

      exception!
    end

    def exception!
      error_message = "HTTP #{verb.upcase}: #{action} Failure: (#{code}) #{message}"
      logger.error(message: error_message, metric: "#{metric_prefix}/exception", payload: {body: body})
      raise(error_class, error_message)
    end

    private

    attr_reader :http_response, :request

    def parse_body
      return unless http_response.class.body_permitted?

      case format
      when :json
        JSON.parse(http_response.body)
      when nil
        http_response.body
      else
        raise(ArgumentError, "Unknown format: #{format.inspect}")
      end

    rescue StandardError => exc
      message = "Failed to parse response body. #{exc.class.name}: #{exc.message}"
      logger.error(message: message, metric: "#{metric_prefix}/exception", exception: exc)
      raise(error_class, message)
    end
  end
end
