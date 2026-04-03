# frozen_string_literal: true

require 'net/http'
require 'open-uri'
require 'uri'
require 'timeout'

module ChipAtlas
  module WabiService
    ENDPOINT = 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/'.freeze

    module_function

    def endpoint_available?
      Timeout.timeout(3) do
        URI.open(ENDPOINT).read == 'chipatlas'
      end
    rescue Timeout::Error, OpenURI::HTTPError, SocketError, Errno::ECONNREFUSED
      false
    end

    def submit_job(params)
      response = Net::HTTP.post_form(URI.parse(ENDPOINT), params)
      body = response.body
      return nil unless body

      id = body.split("\n").find { |l| l =~ /^requestId/ }&.split(/\s/)&.last
      id
    end

    def job_finished?(request_id)
      server_url = 'https://dtn1.ddbj.nig.ac.jp'
      endpoint = "/wabi/chipatlas/#{request_id}?info=result&format=html"

      uri = URI.parse(server_url + endpoint)
      response = Net::HTTP.get_response(uri)
      response.code == '200'
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      nil
    end

    def fetch_log(request_id)
      uri = URI.parse("#{ENDPOINT}#{request_id}?info=result&format=log")
      URI.open(uri.to_s).read
    rescue Timeout::Error, OpenURI::HTTPError, SocketError, Errno::ECONNREFUSED
      nil
    end
  end
end
