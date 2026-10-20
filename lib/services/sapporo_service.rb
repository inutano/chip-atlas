# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'timeout'

module ChipAtlas
  module SapporoService
    ENDPOINT = 'https://ea.chip-atlas.org'
    # The WES runs only the workflows listed in
    # script/sapporo-enrichment-analysis/sapporo_config/executable_workflows.json,
    # and since Sapporo 2.2.0 POST /runs requires workflow_url and workflow_type_version.
    WORKFLOW_URL = 'https://raw.githubusercontent.com/inutano/chip-atlas/master/script/enrichment-analysis/enrichment-analysis.cwl'
    WORKFLOW_TYPE_VERSION = '1.0.0'

    module_function

    def submit_job(params)
      uri = URI.parse("#{ENDPOINT}/runs")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.post(uri.path, URI.encode_www_form(run_request_form(params)))
      return nil unless response.code == '200'

      body = JSON.parse(response.body)
      body['run_id']
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, JSON::ParserError
      nil
    end

    # The form fields of POST /runs. workflow_engine_parameters is never sent:
    # the WES rejects it while it runs only listed workflows.
    def run_request_form(params)
      {
        'workflow_type'         => 'enrichment-analysis',
        'workflow_type_version' => WORKFLOW_TYPE_VERSION,
        'workflow_engine'       => 'enrichment-analysis',
        'workflow_url'          => WORKFLOW_URL,
        'workflow_params'       => JSON.generate(params),
      }
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

  end
end
