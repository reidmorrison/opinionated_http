module OpinionatedHTTP
  # The request object
  class Request
    attr_accessor :action, :verb, :format, :path, :headers, :body, :form_data, :username, :password, :parameters,
                  :metric_prefix, :error_class, :logger

    def initialize(action:, verb: nil, path: nil, format: nil, headers: {}, body: nil, form_data: nil, username: nil, password: nil, parameters: nil)
      @action     = action
      @path       =
        if path.nil?
          "/#{action}"
        elsif path.start_with?("/")
          path
        else
          "/#{path}"
        end
      @verb       = verb
      @format     = format
      @headers    = headers
      @body       = body
      @form_data  = form_data
      @username   = username
      @password   = password
      @parameters = parameters
    end

    def http_request
      unless headers_and_form_data_compatible?(headers, form_data)
        raise(ArgumentError, "Setting form data will overwrite supplied content-type")
      end
      raise(ArgumentError, "Cannot supply both form_data and a body") if body && form_data

      path_with_params = parameters ? "#{path}?#{URI.encode_www_form(parameters)}" : path
      body             = format_body if self.body
      request          = Net::HTTP.const_get(verb).new(path_with_params, headers)

      if body && !request.request_body_permitted?
        raise(ArgumentError, "#{request.class.name} does not support a request body")
      end

      if parameters && !request.response_body_permitted?
        raise(ArgumentError, ":parameters cannot be supplied for #{request.class.name}")
      end

      request.body     = body if body
      request.set_form_data form_data if form_data
      request.basic_auth(username, password) if username && password
      request
    end

    private

    def format_body
      return if body.nil?

      case format
      when :json
        headers["Content-Type"] = "application/json"
        body.to_json #unless body.is_a?(String) || body.nil?
      when nil
        body
      else
        raise(ArgumentError, "Unknown format: #{format.inspect}")
      end
    rescue StandardError => exc
      message = "Failed to serialize request body. #{exc.class.name}: #{exc.message}"
      logger.error(message: message, metric: "#{metric_prefix}/exception", exception: exc)
      raise(error_class, message)
    end

    def headers_and_form_data_compatible?(headers, form_data)
      return true if headers.empty? || form_data.nil?

      !headers.keys.map(&:downcase).include?("content-type")
    end
  end
end
