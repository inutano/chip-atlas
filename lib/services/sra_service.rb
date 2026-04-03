# frozen_string_literal: true

require 'open-uri'
require 'nokogiri'
require 'json'

module ChipAtlas
  class SraService
    EUTILS_BASE = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils'.freeze

    def initialize(exp_id)
      @exp_id = exp_id
    end

    def fetch
      cached = ChipAtlas::SraCache.get(@exp_id)
      return cached if cached

      metadata = fetch_from_ncbi
      ChipAtlas::SraCache.set(@exp_id, metadata) if metadata
      metadata
    end

    private

    def fetch_from_ncbi
      uid = get_uid
      return error_metadata unless uid

      xml = Nokogiri::XML(URI.open("#{EUTILS_BASE}/efetch.fcgi?db=sra&id=#{uid}"))
      parse_experiment(xml)
    rescue OpenURI::HTTPError, Timeout::Error, SocketError, Errno::ECONNREFUSED
      error_metadata
    end

    def get_uid
      url = "#{EUTILS_BASE}/esearch.fcgi?db=sra&term=#{@exp_id}&retmode=json"
      result = JSON.parse(URI.open(url).read)
      ids = result.dig('esearchresult', 'idlist')
      ids&.size == 1 ? ids.first : nil
    rescue OpenURI::HTTPError, Timeout::Error, SocketError, JSON::ParserError
      nil
    end

    def parse_experiment(xml)
      lib_layout_node = xml.at_css('LIBRARY_LAYOUT')&.children&.first

      {
        exp_id: @exp_id,
        library_description: {
          library_name:                  xml.at_css('LIBRARY_NAME')&.text.to_s,
          library_strategy:              xml.at_css('LIBRARY_STRATEGY')&.text.to_s,
          library_source:                xml.at_css('LIBRARY_SOURCE')&.text.to_s,
          library_selection:             xml.at_css('LIBRARY_SELECTION')&.text.to_s,
          library_construction_protocol: xml.at_css('LIBRARY_CONSTRUCTION_PROTOCOL')&.text.to_s,
        },
        platform_information: {
          instrument_model: xml.at_css('INSTRUMENT_MODEL')&.text.to_s,
          cycle_sequence:   xml.at_css('CYCLE_SEQUENCE')&.text.to_s,
          cycle_count:      xml.at_css('CYCLE_COUNT')&.text.to_s,
          flow_sequence:    xml.at_css('FLOW_SEQUENCE')&.text.to_s,
          flow_count:       xml.at_css('FLOW_COUNT')&.text.to_s,
          key_sequence:     xml.at_css('KEY_SEQUENCE')&.text.to_s,
        },
        platform:               xml.at_css('PLATFORM')&.children&.first&.name,
        library_layout:         lib_layout_node&.name,
        library_orientation:    lib_layout_node&.attr('ORIENTATION').to_s,
        library_nominal_length: lib_layout_node&.attr('NOMINAL_LENGTH').to_s,
        library_nominal_sdev:   lib_layout_node&.attr('NOMINAL_SDEV').to_s,
      }
    end

    def error_metadata
      msg = 'ERROR: cannot retrieve data from NCBI'
      {
        exp_id: @exp_id,
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
