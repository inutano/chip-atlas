require 'open-uri'
require 'nokogiri'
require 'json'

module PJ
  class SRA
    def initialize(expid)
      @expid = expid
      @uid = get_uid
      @experiment = ncbi_experiment_data
    end

    def eutils_base
      "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
    end

    def efetch_base
      eutils_base + "/efetch.fcgi"
    end

    def esearch_base
      eutils_base + "/esearch.fcgi"
    end

    def esearch_url
      esearch_base + "?db=sra&term=#{@expid}&retmode=json"
    end

    def get_uid
      uid = JSON.load(open(esearch_url).read)["esearchresult"]["idlist"]
      if uid.size == 1
        uid.first
      end
    rescue OpenURI::HTTPError
      nil
    end

    def efetch_url
      efetch_base + "?db=sra&id=#{@uid}"
    end

    def ncbi_experiment_data
      if @uid
        Nokogiri::XML(open(efetch_url))
      else
        nil
      end
    rescue OpenURI::HTTPError
      nil
    end

    def fetch
      if @experiment
        {
          expid: @expid,
          library_description: library_description,
          platform_information: platform_information,
        }.merge(
          platform
        ).merge(
          lib_layout
        )
      else
        {
          expid: @expid,
          library_description: {
            library_name:                  "ERROR: cannot retrieve data from NCBI: too many requests",
            library_strategy:              "ERROR: cannot retrieve data from NCBI: too many requests",
            library_source:                "ERROR: cannot retrieve data from NCBI: too many requests",
            library_selection:             "ERROR: cannot retrieve data from NCBI: too many requests",
            library_construction_protocol: "ERROR: cannot retrieve data from NCBI: too many requests",
          },
          platform_information: {
            instrument_model: "ERROR: cannot retrieve data from NCBI: too many requests",
            cycle_sequence:   "ERROR: cannot retrieve data from NCBI: too many requests",
            cycle_count:      "ERROR: cannot retrieve data from NCBI: too many requests",
            flow_sequence:    "ERROR: cannot retrieve data from NCBI: too many requests",
            flow_count:       "ERROR: cannot retrieve data from NCBI: too many requests",
            key_sequence:     "ERROR: cannot retrieve data from NCBI: too many requests",
          },
          platform:               "ERROR: cannot retrieve data from NCBI: too many requests",
          library_layout:         "ERROR: cannot retrieve data from NCBI: too many requests",
          library_orientation:    "ERROR: cannot retrieve data from NCBI: too many requests",
          library_nominal_length: "ERROR: cannot retrieve data from NCBI: too many requests",
          library_nominal_sdev:   "ERROR: cannot retrieve data from NCBI: too many requests",
        }
      end
    end

    def library_description
      {
        library_name:                  @experiment.css("LIBRARY_NAME").inner_text,
        library_strategy:              @experiment.css("LIBRARY_STRATEGY").inner_text,
        library_source:                @experiment.css("LIBRARY_SOURCE").inner_text,
        library_selection:             @experiment.css("LIBRARY_SELECTION").inner_text,
        library_construction_protocol: @experiment.css("LIBRARY_CONSTRUCTION_PROTOCOL").inner_text,
      }
    end

    def platform_information
      {
        instrument_model: @experiment.css("INSTRUMENT_MODEL").inner_text,
        cycle_sequence:   @experiment.css("CYCLE_SEQUENCE").inner_text,
        cycle_count:      @experiment.css("CYCLE_COUNT").inner_text,
        flow_sequence:    @experiment.css("FLOW_SEQUENCE").inner_text,
        flow_count:       @experiment.css("FLOW_COUNT").inner_text,
        key_sequence:     @experiment.css("KEY_SEQUENCE").inner_text,
      }
    end

    def platform
      { platform: @experiment.css("PLATFORM").first.children[0].name }
    rescue
      {}
    end

    def lib_layout
      lib_layout = @experiment.css("LIBRARY_LAYOUT").first.children[0]
      {
        library_layout:         lib_layout.name,
        library_orientation:    lib_layout.attr("ORIENTATION").to_s,
        library_nominal_length: lib_layout.attr("NOMINAL_LENGTH").to_s,
        library_nominal_sdev:   lib_layout.attr("NOMINAL_SDEV").to_s
      }
    rescue
      {}
    end
  end
end
