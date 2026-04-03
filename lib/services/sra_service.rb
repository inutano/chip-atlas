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
      {
        exp_id: @exp_id,
        library_description: {
          library_name:                  xml.css('LIBRARY_NAME').inner_text,
          library_strategy:              xml.css('LIBRARY_STRATEGY').inner_text,
          library_source:                xml.css('LIBRARY_SOURCE').inner_text,
          library_selection:             xml.css('LIBRARY_SELECTION').inner_text,
          library_construction_protocol: xml.css('LIBRARY_CONSTRUCTION_PROTOCOL').inner_text,
        },
        platform_information: {
          instrument_model: xml.css('INSTRUMENT_MODEL').inner_text,
          cycle_sequence:   xml.css('CYCLE_SEQUENCE').inner_text,
          cycle_count:      xml.css('CYCLE_COUNT').inner_text,
          flow_sequence:    xml.css('FLOW_SEQUENCE').inner_text,
          flow_count:       xml.css('FLOW_COUNT').inner_text,
          key_sequence:     xml.css('KEY_SEQUENCE').inner_text,
        },
        platform:               (xml.css('PLATFORM').first&.children&.first&.name rescue nil),
        library_layout:         (xml.css('LIBRARY_LAYOUT').first&.children&.first&.name rescue nil),
        library_orientation:    (xml.css('LIBRARY_LAYOUT').first&.children&.first&.attr('ORIENTATION').to_s rescue ''),
        library_nominal_length: (xml.css('LIBRARY_LAYOUT').first&.children&.first&.attr('NOMINAL_LENGTH').to_s rescue ''),
        library_nominal_sdev:   (xml.css('LIBRARY_LAYOUT').first&.children&.first&.attr('NOMINAL_SDEV').to_s rescue ''),
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
