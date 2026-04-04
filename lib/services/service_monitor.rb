# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'timeout'

module ChipAtlas
  # Monitors external service availability with cached status.
  # All checks are non-blocking with short timeouts.
  # Status is refreshed at most once per CHECK_INTERVAL seconds.
  module ServiceMonitor
    CHECK_INTERVAL = 60  # seconds

    SERVICES = {
      data_server: 'https://chip-atlas.dbcls.jp/data/metadata/experimentList.tab',
      wabi:        'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/',
      wes:         'https://ea.chip-atlas.org/service-info',
    }.freeze

    @statuses = {}
    @checked_at = {}

    module_function

    def status(service)
      service = service.to_sym
      now = Time.now

      if @checked_at[service] && (now - @checked_at[service]) < CHECK_INTERVAL
        return @statuses[service]
      end

      @statuses[service] = check(service)
      @checked_at[service] = now
      @statuses[service]
    end

    def all_statuses
      SERVICES.each_key { |s| status(s) }

      data = @statuses[:data_server]
      compute = @statuses[:wabi] || @statuses[:wes]

      features = {
        peak_browser:         data ? 'ok' : 'unavailable',
        colo:                 data ? 'ok' : 'unavailable',
        target_genes:         data ? 'ok' : 'unavailable',
        search:               'ok',
        enrichment_analysis:  enrichment_feature_status(data, compute),
        diff_analysis:        data && @statuses[:wabi] ? 'ok' : 'unavailable',
      }

      {
        services: {
          data_server: @statuses[:data_server] ? 'ok' : 'down',
          wabi:        @statuses[:wabi] ? 'ok' : 'down',
          wes:         @statuses[:wes] ? 'ok' : 'down',
        },
        features: features,
      }
    end

    def data_server_available?
      status(:data_server)
    end

    def check(service)
      url = SERVICES[service]
      return false unless url

      Timeout.timeout(8) do
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 5
        response = http.request_head(uri.request_uri)
        response.code.to_i < 500
      end
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED,
           Net::HTTPError, Net::OpenTimeout, OpenSSL::SSL::SSLError
      false
    end

    def enrichment_feature_status(data, compute)
      return 'unavailable' unless data
      return 'unavailable' unless compute

      @statuses[:wabi] ? 'ok' : 'ok (backup)'
    end

    private_class_method :check, :enrichment_feature_status
  end
end
