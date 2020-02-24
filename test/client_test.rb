require 'net/http'
require 'json'
require_relative 'test_helper'

module OpinionatedHTTP
  class ClientTest < Minitest::Test
    describe OpinionatedHTTP::Client do
      class ServiceError < StandardError
      end

      let :http do
        OpinionatedHTTP.new(
          secret_config_prefix: 'fake_service',
          metric_prefix:        'FakeService',
          logger:               SemanticLogger["FakeService"],
          error_class:          ServiceError,
          header:               {'Content-Type' => 'application/json'}
        )
      end

      describe "get" do
        it 'success' do
          # output   = {zip: '12345', population: 54321}
          # body     = output.to_json
          # response = Net::HTTPSuccess.new(200, 'OK', body)
          # http.driver.stub(:request, response) do
          #   http.get(action: 'lookup', parameters: {zip: '12345'})
          # end
        end
      end
    end
  end
end
