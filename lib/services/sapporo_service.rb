# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'timeout'

module ChipAtlas
  module SapporoService
    ENDPOINT = 'https://ea.chip-atlas.org'

    module_function

    def endpoint_available?
      now = Time.now
      if @checked_at && (now - @checked_at) < 60
        return @available
      end

      @available = check_endpoint
      @checked_at = now
      @available
    end

    def submit_job(params)
      uri = URI.parse("#{ENDPOINT}/runs")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      form_data = {
        'workflow_type'   => 'enrichment-analysis',
        'workflow_engine' => 'enrichment-analysis',
        'workflow_params' => JSON.generate(params),
      }

      response = http.post(uri.path, URI.encode_www_form(form_data))
      return nil unless response.code == '200'

      body = JSON.parse(response.body)
      body['run_id']
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError
      nil
    end

    def job_status(run_id)
      uri = URI.parse("#{ENDPOINT}/runs/#{run_id}/status")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.get(uri.request_uri)
      return nil unless response.code == '200'

      state = JSON.parse(response.body)['state']
      case state
      when 'COMPLETE'       then 'finished'
      when 'EXECUTOR_ERROR' then 'error'
      when 'RUNNING', 'INITIALIZING', 'QUEUED' then 'running'
      when 'CANCELED'       then 'canceled'
      else 'running'
      end
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError
      nil
    end

    def result_url(run_id)
      "https://chip-atlas.dbcls.jp/data/enrichment-analysis/#{run_id}/#{run_id}.result.html"
    end

    def result_tsv_url(run_id)
      "https://chip-atlas.dbcls.jp/data/enrichment-analysis/#{run_id}/#{run_id}.result.tsv"
    end

    def fetch_log(run_id)
      uri = URI.parse("#{ENDPOINT}/runs/#{run_id}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.get(uri.request_uri)
      return nil unless response.code == '200'

      data = JSON.parse(response.body)
      data['run_log']&.dig('stderr') || data.dig('run_log', 'stdout')
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError
      nil
    end

    def check_endpoint
      Timeout.timeout(3) do
        uri = URI.parse("#{ENDPOINT}/service-info")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 3
        http.read_timeout = 3
        response = http.get(uri.path)
        response.code == '200'
      end
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      false
    end

    private_class_method :check_endpoint
  end
end
