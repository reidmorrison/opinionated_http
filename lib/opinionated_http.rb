require "opinionated_http/version"
#
# Opinionated HTTP
#
# An opinionated HTTP Client library using convention over configuration.
#
module OpinionatedHTTP
  autoload :Client, "opinionated_http/client"
  autoload :Logger, "opinionated_http/logger"
  autoload :Request, "opinionated_http/request"
  autoload :Response, "opinionated_http/response"

  #
  # Create a new Opinionated HTTP instance.
  #
  # See README.md for more info.
  def self.new(**args)
    Client.new(**args)
  end
end
