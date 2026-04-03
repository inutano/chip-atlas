# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'timeout'

module ChipAtlas
  module WabiService
    ENDPOINT = 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/'

    module_function

    def endpoint_available?
      Timeout.timeout(3) do
        uri = URI.parse(ENDPOINT)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 3
        http.read_timeout = 3
        response = http.get(uri.path)
        response.body == 'chipatlas'
      end
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      false
    end

    def submit_job(params)
      response = Net::HTTP.post_form(URI.parse(ENDPOINT), params)
      body = response.body
      return nil unless body

      body.split("\n").find { |l| l.start_with?('requestId') }&.split(/\s/)&.last
    end

    def job_finished?(request_id)
      uri = URI.parse("#{ENDPOINT}#{request_id}?info=result&format=html")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.request_head(uri.request_uri)
      response.code == '200'
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      nil
    end

    def fetch_log(request_id)
      uri = URI.parse("#{ENDPOINT}#{request_id}?info=result&format=log")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.get(uri.request_uri)
      response.code == '200' ? response.body : nil
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      nil
    end
  end
end
