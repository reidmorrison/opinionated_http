require "net/http"
require "json"
require_relative "test_helper"

class ClientTest < Minitest::Test
  describe OpinionatedHTTP::Client do
    class ServiceError < StandardError
    end

    let :http do
      OpinionatedHTTP.new(
        secret_config_prefix: "fake_service",
        metric_prefix:        "FakeService",
        logger:               SemanticLogger["FakeService"],
        error_class:          ServiceError,
        header:               {"Content-Type" => "application/json"}
      )
    end

    describe "get" do
      it "succeeds" do
        output = {zip: "12345", population: 54_321}
        body   = output.to_json
        stub_request(Net::HTTPSuccess, 200, "OK", body) do
          response = http.get(action: "lookup", parameters: {zip: "12345"})
          assert_equal body, response.body!
        end
      end

      it "fails" do
        message = "HTTP GET: lookup Failure: (403) Forbidden"
        error   = assert_raises ServiceError do
          stub_request(Net::HTTPForbidden, 403, "Forbidden", "") do
            response = http.get(action: "lookup", parameters: {zip: "12345"})
            response.body!
          end
        end
        assert_equal message, error.message
      end
    end

    describe "post" do
      it "succeeds with body" do
        output = {zip: "12345", population: 54_321}
        body   = output.to_json
        stub_request(Net::HTTPSuccess, 200, "OK", body) do
          response = http.post(action: "lookup", body: body)
          assert_equal body, response.body!
        end
      end

      it "with form data" do
        output = {zip: "12345", population: 54_321}
        body   = output.to_json
        stub_request(Net::HTTPSuccess, 200, "OK", body) do
          response = http.post(action: "lookup", form_data: output)
          assert_equal body, response.body!
        end
      end

      it "fails with body" do
        message = "HTTP POST: lookup Failure: (403) Forbidden"
        output  = {zip: "12345", population: 54_321}
        body    = output.to_json
        error   = assert_raises ServiceError do
          stub_request(Net::HTTPForbidden, 403, "Forbidden", "") do
            response = http.post(action: "lookup", body: body)
            response.body!
          end
        end
        assert_equal message, error.message
      end

      it "fails with form data" do
        output  = {zip: "12345", population: 54_321}
        message = "HTTP POST: lookup Failure: (403) Forbidden"
        error   = assert_raises ServiceError do
          stub_request(Net::HTTPForbidden, 403, "Forbidden", "") do
            response = http.post(action: "lookup", form_data: output)
            response.body!
          end
        end
        assert_equal message, error.message
      end
    end

    def stub_request(klass, code, msg, body, &block)
      response = klass.new("1.1", code, msg)
      response.stub(:body, body) do
        http.driver.stub(:request, response, &block)
      end
    end
  end
end
