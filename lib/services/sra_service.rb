# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'rexml/document'
require 'json'

module ChipAtlas
  class SraService
    EUTILS_BASE = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils'

    TEST_ENV_VALUES = %w[test].freeze

    # Raised when a test would make a live request to NCBI eutils because no
    # http_get stub was installed. Mirrors DataProxy::LiveFetchNotStubbed /
    # ColoTsv::LiveFetchNotStubbed / TargetGenesTsv::LiveFetchNotStubbed --
    # exists so a forgotten stub fails loudly under RACK_ENV=test instead of
    # silently falling into fetch_from_ncbi's rescue clause.
    LiveFetchNotStubbed = Class.new(StandardError)

    @http_get = nil

    class << self
      # Test-only hook: replace the real HTTP GET with a stub. `callable` is
      # invoked as `callable.call(url)` and must return the response body
      # (String) or nil (request failed / non-200).
      attr_accessor :http_get
    end

    def initialize(experiment_id)
      @experiment_id = experiment_id
    end

    # SV-34: only a metadata hash that actually came from NCBI is cached --
    # a failure (fetch_from_ncbi returning nil) is never stored, so the next
    # view retries NCBI instead of replaying "ERROR: cannot retrieve data
    # from NCBI" to every visitor for SraCache::TTL_SECONDS (30 days).
    def fetch
      cached = ChipAtlas::SraCache.get(@experiment_id)
      return cached if cached

      metadata = fetch_from_ncbi
      return error_metadata unless metadata

      ChipAtlas::SraCache.set(@experiment_id, metadata)
      metadata
    end

    private

    def http_get(url)
      return self.class.http_get.call(url) if self.class.http_get

      raise_if_unstubbed_under_test!(url)

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 15
      response = http.get(uri.request_uri)
      response.body if response.code == '200'
    end

    def raise_if_unstubbed_under_test!(url)
      return unless TEST_ENV_VALUES.include?(ENV['RACK_ENV']) || TEST_ENV_VALUES.include?(ENV['APP_ENV'])

      raise LiveFetchNotStubbed,
            "SraService would make a live request to #{url} under " \
            "RACK_ENV=#{ENV['RACK_ENV'].inspect}/APP_ENV=#{ENV['APP_ENV'].inspect}. " \
            'Stub ChipAtlas::SraService.http_get= in this test.'
    end

    def fetch_from_ncbi
      uid = get_uid
      return nil unless uid

      xml_str = http_get("#{EUTILS_BASE}/efetch.fcgi?db=sra&id=#{uid}")
      return nil unless xml_str

      doc = REXML::Document.new(xml_str)
      parse_experiment(doc)
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, REXML::ParseException
      nil
    end

    def get_uid
      body = http_get("#{EUTILS_BASE}/esearch.fcgi?db=sra&term=#{@experiment_id}&retmode=json")
      return nil unless body

      result = JSON.parse(body)
      ids = result.dig('esearchresult', 'idlist')
      ids&.size == 1 ? ids.first : nil
    rescue SocketError, Timeout::Error, JSON::ParserError
      nil
    end

    def parse_experiment(doc)
      lib_layout_el = doc.elements['.//LIBRARY_LAYOUT']&.elements&.first

      {
        experiment_id: @experiment_id,
        library_description: {
          library_name:                  xml_text(doc, 'LIBRARY_NAME'),
          library_strategy:              xml_text(doc, 'LIBRARY_STRATEGY'),
          library_source:                xml_text(doc, 'LIBRARY_SOURCE'),
          library_selection:             xml_text(doc, 'LIBRARY_SELECTION'),
          library_construction_protocol: xml_text(doc, 'LIBRARY_CONSTRUCTION_PROTOCOL'),
        },
        platform_information: {
          instrument_model: xml_text(doc, 'INSTRUMENT_MODEL'),
          cycle_sequence:   xml_text(doc, 'CYCLE_SEQUENCE'),
          cycle_count:      xml_text(doc, 'CYCLE_COUNT'),
          flow_sequence:    xml_text(doc, 'FLOW_SEQUENCE'),
          flow_count:       xml_text(doc, 'FLOW_COUNT'),
          key_sequence:     xml_text(doc, 'KEY_SEQUENCE'),
        },
        platform:               doc.elements['.//PLATFORM']&.elements&.first&.name,
        library_layout:         lib_layout_el&.name,
        library_orientation:    lib_layout_el&.attributes&.[]('ORIENTATION').to_s,
        library_nominal_length: lib_layout_el&.attributes&.[]('NOMINAL_LENGTH').to_s,
        library_nominal_sdev:   lib_layout_el&.attributes&.[]('NOMINAL_SDEV').to_s,
      }
    end

    def xml_text(doc, tag)
      doc.elements[".//#{tag}"]&.text.to_s
    end

    def error_metadata
      msg = 'ERROR: cannot retrieve data from NCBI'
      {
        experiment_id: @experiment_id,
        library_description: {
          library_name: msg, library_strategy: msg, library_source: msg,
          library_selection: msg, library_construction_protocol: msg,
        },
        platform_information: {
          instrument_model: msg, cycle_sequence: msg, cycle_count: msg,
          flow_sequence: msg, flow_count: msg, key_sequence: msg,
        },
        platform: msg,
        library_layout: msg,
        library_orientation: '',
        library_nominal_length: '',
        library_nominal_sdev: '',
      }
    end
  end
end
