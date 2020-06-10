require "net/http"
require "json"
require_relative "test_helper"

module OpinionatedHTTP
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
          output   = {zip: "12345", population: 54_321}
          body     = output.to_json
          response = stub_request(Net::HTTPSuccess, 200, "OK", body) do
            http.get(action: "lookup", parameters: {zip: "12345"})
          end
          assert_equal body, response
        end

        it "fails" do
          message = "HTTP GET: lookup Failure: (403) Forbidden"
          error = assert_raises ServiceError do
            stub_request(Net::HTTPForbidden, 403, "Forbidden", "") do
              http.get(action: "lookup", parameters: {zip: "12345"})
            end
          end
          assert_equal message, error.message
        end
      end

      describe "post" do
        it "succeeds with body" do
          output   = {zip: "12345", population: 54_321}
          body     = output.to_json
          response = stub_request(Net::HTTPSuccess, 200, "OK", body) do
            http.post(action: "lookup", body: body)
          end
          assert_equal body, response
        end

        it "with form data" do
          output   = {zip: "12345", population: 54_321}
          body     = output.to_json
          response = stub_request(Net::HTTPSuccess, 200, "OK", body) do
            http.post(action: "lookup", form_data: output)
          end
          assert_equal body, response
        end

        it "fails with body" do
          message = "HTTP POST: lookup Failure: (403) Forbidden"
          output  = {zip: "12345", population: 54_321}
          body    = output.to_json
          error   = assert_raises ServiceError do
            stub_request(Net::HTTPForbidden, 403, "Forbidden", "") do
              http.post(action: "lookup", body: body)
            end
          end
          assert_equal message, error.message
        end

        it "fails with form data" do
          output  = {zip: "12345", population: 54_321}
          message = "HTTP POST: lookup Failure: (403) Forbidden"
          error   = assert_raises ServiceError do
            stub_request(Net::HTTPForbidden, 403, "Forbidden", "") do
              http.post(action: "lookup", form_data: output)
            end
          end
          assert_equal message, error.message
        end
      end

      describe "build_request" do
        let(:path) { "/fake_action" }
        let(:post_verb) { "Post" }
        let(:get_verb) { "Get" }

        it "creates a request corresponding to the supplied verb" do
          req  = http.build_request(path: path, verb: post_verb)
          req2 = http.build_request(path: path, verb: get_verb)

          assert_kind_of Net::HTTP::Post, req
          assert_kind_of Net::HTTP::Get, req2
        end

        it "returns a request with supplied headers" do
          test_headers = {"test1" => "yes_test_1", "test2" => "yes_test_2"}
          req          = http.build_request(path: path, verb: get_verb, headers: test_headers)

          assert_equal test_headers["test1"], req["test1"]
          assert_equal test_headers["test2"], req["test2"]
        end

        it "returns a request with supplied body" do
          test_body = "nice bod"
          req       = http.build_request(path: path, verb: post_verb, body: test_body)

          assert_equal test_body, req.body
        end

        it "returns a request with supplied form data in x-www-form-urlencoded Content-Type" do
          test_data       = {test1: "yes", test2: "no"}
          expected_string = "test1=yes&test2=no"
          req             = http.build_request(path: path, verb: post_verb, form_data: test_data)

          assert_equal expected_string, req.body
          assert_equal "application/x-www-form-urlencoded", req["Content-Type"]
        end

        it "add supplied authentication to the request" do
          test_un = "admin"
          test_pw = "hunter2"
          req     = http.build_request(path: path, verb: get_verb, username: test_un, password: test_pw)
          req2    = Net::HTTP::Get.new(path)
          req2.basic_auth test_un, test_pw

          assert_equal req2["authorization"], req["authorization"]
        end

        it "raise an error if supplied content-type header would be overwritten by setting form_data" do
          downcase_headers    = {"unimportant" => "blank", "content-type" => "application/json"}
          capitalized_headers = {"Unimportant" => "blank", "Content-Type" => "application/json"}
          no_conflict_headers = {"whatever" => "blank", "irrelevant" => "test"}
          form_data           = {thing1: 1, thing2: 2}

          assert_raises ArgumentError do
            http.build_request(path: path, verb: post_verb, headers: downcase_headers, form_data: form_data)
          end

          assert_raises ArgumentError do
            http.build_request(path: path, verb: post_verb, headers: capitalized_headers, form_data: form_data)
          end

          assert http.build_request(path: path, verb: post_verb, headers: no_conflict_headers, form_data: form_data)
        end

        it "raise an error if there is a collision between supplied body and form_data" do
          form_data = {thing1: 1, thing2: 2}
          body      = "not form data"

          assert_raises ArgumentError do
            http.build_request(path: path, verb: post_verb, body: body, form_data: form_data)
          end

          assert http.build_request(path: path, verb: post_verb, body: body)
          assert http.build_request(path: path, verb: post_verb, form_data: form_data)
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
end
