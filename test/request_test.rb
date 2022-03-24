require "net/http"
require "json"
require_relative "test_helper"

class RequestTest < Minitest::Test
  describe OpinionatedHTTP::Request do
    describe "http_request" do
      let(:path) { "/fake_action" }
      let(:post_verb) { "Post" }
      let(:get_verb) { "Get" }
      let(:action) { "fake_action" }
      let :json_request do
        {zip: "12345", population: 54_321}
      end

      it "creates a request corresponding to the supplied verb" do
        req  = OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb).http_request
        req2 = OpinionatedHTTP::Request.new(action: action, path: path, verb: get_verb).http_request

        assert_kind_of Net::HTTP::Post, req
        assert_kind_of Net::HTTP::Get, req2
      end

      it "creates a JSON request" do
        req = OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, format: :json, body: json_request).http_request

        assert_equal json_request.to_json, req.body
        assert_equal "application/json", req["content-type"], -> { req.to_hash.ai }
        assert_equal "application/json", req["accept"], -> { req.to_hash.ai }
      end

      it "returns a request with supplied headers" do
        test_headers = {"test1" => "yes_test_1", "test2" => "yes_test_2"}
        req          = OpinionatedHTTP::Request.new(action: action, path: path, verb: get_verb, headers: test_headers).http_request

        assert_equal test_headers["test1"], req["test1"]
        assert_equal test_headers["test2"], req["test2"]
      end

      it "returns a request with supplied body" do
        test_body = "nice bod"
        req       = OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, body: test_body).http_request

        assert_equal test_body, req.body
      end

      it "returns a request with supplied form data in x-www-form-urlencoded Content-Type" do
        test_data       = {test1: "yes", test2: "no"}
        expected_string = "test1=yes&test2=no"
        req             = OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, form_data: test_data).http_request

        assert_equal expected_string, req.body
        assert_equal "application/x-www-form-urlencoded", req["Content-Type"]
      end

      it "add supplied authentication to the request" do
        test_un = "admin"
        test_pw = "hunter2"
        req     = OpinionatedHTTP::Request.new(action: action, path: path, verb: get_verb, username: test_un, password: test_pw).http_request
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
          OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, headers: downcase_headers, form_data: form_data).http_request
        end

        assert_raises ArgumentError do
          OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, headers: capitalized_headers, form_data: form_data).http_request
        end

        assert OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, headers: no_conflict_headers, form_data: form_data).http_request
      end

      it "raise an error if there is a collision between supplied body and form_data" do
        form_data = {thing1: 1, thing2: 2}
        body      = "not form data"

        assert_raises ArgumentError do
          OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, body: body, form_data: form_data).http_request
        end

        assert OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, body: body).http_request
        assert OpinionatedHTTP::Request.new(action: action, path: path, verb: post_verb, form_data: form_data).http_request
      end
    end
  end
end
