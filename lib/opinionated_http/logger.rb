# Hack to make PersistentHTTP log to the standard logger
# and to make it and GenePool log trace info as trace.
module OpinionatedHTTP
  class Logger
    attr_reader :logger

    def initialize(logger)
      @logger = logger
    end

    def <<(message)
      return unless logger.trace?

      message = message.strip
      return if message.blank?

      logger.trace(message)
    end

    def debug(*args, &block)
      logger.trace(*args, &block)
    end

    def info(*args, &block)
      logger.info(*args, &block)
    end

    def warn(*args, &block)
      logger.warn(*args, &block)
    end

    def error(*args, &block)
      logger.error(*args, &block)
    end
  end
end
