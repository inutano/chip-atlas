class Experiment < ActiveRecord::Base
  class << self
    def list_of_facets
      [ :agClass, :agSubClass, :clClass, :clSubClass ]
    end
    
    def list_of_genome
      [ "hg19", "mm9", "dm3", "ce10", "sacCer3"]
      # self.all.map{|r| r.genome }.uniq
    end
    
    ## Methods to display facets
    
    def index_by_genome(genome)
      records = records_by_genome(genome)
      index_all_facets(records)
    end
    
    def deep_index_by_genome(genome)
      records = records_by_genome(genome)
      deep_index(records)
    end

    def records_by_genome(genome)
      self.where(:genome => genome)
    end
    
    def index_all_genome
      result = Hash.new
      list_of_genome.map do |genome|
        result[genome] = index_by_genome(genome)
      end
      result
    end
    
    def deep_index_all_genome
      result = Hash.new
      list_of_genome.map do |genome|
        result[genome] = deep_index_by_genome(genome)
      end
      result
    end
    
    def index_all_facets(records)
      index = { :antigen => {}, :celltype => {} }
      records.each do |record|
        agClass    = record.agClass
        agSubClass = record.agSubClass
        clClass    = record.clClass
        clSubClass = record.clSubClass
        
        index[:antigen][agClass] ||= Hash.new(0)
        index[:antigen][agClass][agSubClass] += 1

        index[:celltype][clClass] ||= Hash.new(0)
        index[:celltype][clClass][clSubClass] += 1
      end
      index
    end
    
    def empty_index
      {
        antigen: {},
        celltype: {}
      }
    end
    
    def deep_index(records)
      index = empty_index
      records.each do |record|
        agClass    = record.agClass
        agSubClass = record.agSubClass
        clClass    = record.clClass
        clSubClass = record.clSubClass
        
        index[:antigen][agClass] ||= {}
        index[:antigen][agClass][clClass] ||= Hash.new(0)
        index[:antigen][agClass][clClass][agSubClass] += 1

        index[:antigen][agClass]["All cell types"] ||= Hash.new(0)
        index[:antigen][agClass]["All cell types"][agSubClass] += 1
        
        index[:celltype][clClass] ||= {}
        index[:celltype][clClass][agClass] ||= Hash.new(0)
        index[:celltype][clClass][agClass][clSubClass] += 1

        index[:celltype][clClass]["All antigens"] ||= Hash.new(0)
        index[:celltype][clClass]["All antigens"][clSubClass] += 1
      end
      index
    end
    
    def bulk_index(records)
      index = Hash.new
      list_of_facets.each do |facet|
        index[facet] = index_with_experiment_count(records, facet)
      end
      index
    end
    
    def index_with_experiment_count(records, column)
      index = Hash.new(0)
      records.each{|n| index[n.send(column)] += 1 }
      index
    end
    
    ## Methods for experiment detail template
    
    def id_valid?(expid)
      !self.where(:expid => expid).empty?
    end
    
    def record_by_expid(expid)
      records = self.where(:expid => expid)
      raise NameError if records.size > 1
      record = records.first
      { 
        :expid      => expid,
        :genome     => record.genome,
        :agClass    => record.agClass,
        :agSubClass => record.agSubClass,
        :clClass    => record.clClass,
        :clSubClass => record.clSubClass,
        :title      => record.title,
        :attributes => record.additional_attributes,
        :readInfo   => record.readInfo,
        :clSubClassInfo => record.clSubClassInfo,
       }
    end
    
    def fetch_ncbi_metadata(expid)
      url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=sra&id=#{expid}"
      experiment = Nokogiri::XML(open(url))
      { expid: expid,
        library_description: {
          library_name:                  experiment.css("LIBRARY_NAME").inner_text,
          library_strategy:              experiment.css("LIBRARY_STRATEGY").inner_text,
          library_source:                experiment.css("LIBRARY_SOURCE").inner_text,
          library_selection:             experiment.css("LIBRARY_SELECTION").inner_text,
          library_layout:                experiment.css("LIBRARY_LAYOUT").first.children[0].name,
          library_orientation:           experiment.css("LIBRARY_LAYOUT").first.children[0].attr("ORIENTATION").to_s,
          library_nominal_length:        experiment.css("LIBRARY_LAYOUT").first.children[0].attr("NOMINAL_LENGTH").to_s,
          library_nominal_sdev:          experiment.css("LIBRARY_LAYOUT").first.children[0].attr("NOMINAL_SDEV").to_s,
          library_construction_protocol: experiment.css("LIBRARY_CONSTRUCTION_PROTOCOL").inner_text,
        },
        platform_information: {
          platform:         experiment.css("PLATFORM").first.children[0].name,
          instrument_model: experiment.css("INSTRUMENT_MODEL").inner_text,
          cycle_sequence:   experiment.css("CYCLE_SEQUENCE").inner_text,
          cycle_count:      experiment.css("CYCLE_COUNT").inner_text,
          flow_sequence:    experiment.css("FLOW_SEQUENCE").inner_text,
          flow_count:       experiment.css("FLOW_COUNT").inner_text,
          key_sequence:     experiment.css("KEY_SEQUENCE").inner_text,
        }
      }
    end
  end
end

class Bedfile < ActiveRecord::Base
  class << self
    def list_of_facets
      [ :agClass, :agSubClass, :clClass, :clSubClass, :qval ]
    end
    
    def qval_range
      self.all.map{|r| r.qval }.uniq
    end
    
    def list_of_genome
      self.all.map{|r| r.genome }.uniq
    end
    
    def index_all_genome
      index = Hash.new
      list_of_genome.each do |genome|
        index[genome] = index_by_genome(genome)
      end
      index
    end
    
    def index_by_genome(genome)
      records = records_by_genome(genome)
      index_all_facets(records)
    end

    def records_by_genome(genome)
      self.where(:genome => genome)
    end

    def index_all_facets(records)
      index = Hash.new
      list_of_facets.each do |facet|
        index[facet] = index_with_experiment_count(records, facet)
      end
      index
    end
    
    def index_with_experiment_count(records, column)
      index = Hash.new(0)
      records.each do |r|
        c_value = r.send(column)
        experiments = r.experiments
        num_experiments = if experiments
                            experiments.split(",").size
                          else
                            0
                          end
        index[c_value] += num_experiments
      end
      index
    end
    
    def get_filename(condition)
      results = filesearch(condition)
      raise NameError if results.size != 1
      results.first.filename
    end
    # http://localhost:60151/load?file=http://dbarchive.biosciencedbc.jp/kyushu-u/hg19/assembled/#{fname}&genome=hg19
    
    def filesearch(condition)
      self.where(:genome => condition["genome"])
        .where(:agClass => condition["agClass"])
        .where(:agSubClass => condition["agSubClass"] || "-")
        .where(:clClass => condition["clClass"])
        .where(:clSubClass => condition["clSubClass"] || "-")
        .where(:qval => condition["qval"])
    end
  end
end
