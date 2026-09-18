# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module ChipAtlas
  # Fetches data from the chip-atlas.dbcls.jp data server.
  # Used by the API to proxy colo and target_genes result data
  # so agents and the frontend don't need direct CORS access.
  module DataProxy
    DATA_HOST = 'chip-atlas.dbcls.jp'

    TEST_ENV_VALUES = %w[test].freeze

    # Raised when a test would reach the real data server because no
    # fetcher stub was installed. Mirrors ColoTsv::LiveFetchNotStubbed and
    # TargetGenesTsv::LiveFetchNotStubbed -- exists so a forgotten stub
    # fails loudly under RACK_ENV=test instead of silently making a real
    # HTTPS request. Note this guard only protects local test runs where
    # the sandbox additionally blocks the socket (`--network none`); CI
    # (.github/workflows/ci.yml) runs the Ruby suite on a GitHub-hosted
    # runner with no such network isolation, so this in-code guard is the
    # only thing standing between an unstubbed test and a real request to
    # chip-atlas.dbcls.jp there.
    LiveFetchNotStubbed = Class.new(StandardError)

    @fetcher = nil

    module_function

    # Test-only hook: replace the network fetch with a stub. `callable` is
    # invoked as `callable.call(url)` and must return the response body
    # (String) or nil (not found).
    def fetcher=(callable)
      @fetcher = callable
    end

    def fetch(url)
      return @fetcher.call(url) if @fetcher

      raise_if_unstubbed_under_test!(url)
      fetch_live(url)
    end

    def raise_if_unstubbed_under_test!(url)
      return unless TEST_ENV_VALUES.include?(ENV['RACK_ENV']) || TEST_ENV_VALUES.include?(ENV['APP_ENV'])

      raise LiveFetchNotStubbed,
            "DataProxy would make a live request to #{url} under " \
            "RACK_ENV=#{ENV['RACK_ENV'].inspect}/APP_ENV=#{ENV['APP_ENV'].inspect}. " \
            'Stub ChipAtlas::DataProxy.fetcher= in this test.'
    end

    def fetch_live(url)
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

    private_class_method :raise_if_unstubbed_under_test!, :fetch_live
  end
end
