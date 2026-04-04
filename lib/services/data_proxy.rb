# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module ChipAtlas
  # Fetches JSON data from the chip-atlas.dbcls.jp data server.
  # Used by the API to proxy colo and target_genes result data
  # so agents and the frontend don't need direct CORS access.
  module DataProxy
    DATA_HOST = 'chip-atlas.dbcls.jp'

    module_function

    def fetch_json(url)
      uri = URI.parse(url)
      return nil unless uri.host == DATA_HOST

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      response = http.get(uri.request_uri)

      return nil unless response.code == '200'
      response.body
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError
      nil
    end
  end
end
