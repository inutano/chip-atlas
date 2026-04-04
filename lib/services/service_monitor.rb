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

      features = {
        peak_browser:         @statuses[:data_server] ? 'ok' : 'unavailable',
        colo:                 @statuses[:data_server] ? 'ok' : 'unavailable',
        target_genes:         @statuses[:data_server] ? 'ok' : 'unavailable',
        search:               'ok',
        enrichment_analysis:  enrichment_status,
        diff_analysis:        @statuses[:wabi] ? 'ok' : 'unavailable',
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

    def enrichment_status
      if @statuses[:wabi]
        'ok'
      elsif @statuses[:wes]
        'ok (backup)'
      else
        'unavailable'
      end
    end

    private_class_method :check, :enrichment_status
  end
end
