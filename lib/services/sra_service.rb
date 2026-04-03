# frozen_string_literal: true

require 'open-uri'
require 'rexml/document'
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

      xml_str = URI.open("#{EUTILS_BASE}/efetch.fcgi?db=sra&id=#{uid}").read
      doc = REXML::Document.new(xml_str)
      parse_experiment(doc)
    rescue OpenURI::HTTPError, Timeout::Error, SocketError, Errno::ECONNREFUSED, REXML::ParseException
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

    def parse_experiment(doc)
      lib_layout_el = doc.elements['.//LIBRARY_LAYOUT']&.elements&.first

      {
        exp_id: @exp_id,
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
