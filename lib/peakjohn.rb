class Experiment < ActiveRecord::Base
  class << self
    def list_of_facets
      [ :agClass, :agSubClass, :clClass, :clSubClass ]
    end
    
    def list_of_genome
      self.all.map{|r| r.genome }.uniq
    end
    
    ## Methods to display facets
    
    def index_by_genome(genome)
      records = records_by_genome(genome)
      index_all_facets(records)
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
      { :expid      => expid,
        :genome     => record.genome,
        :agClass    => record.agClass,
        :agSubClass => record.agSubClass,
        :clClass    => record.clClass,
        :clSubClass => record.clSubClass,
        :title      => record.title,
        :attributes => record.additional_attributes }
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
      raise NameError if results.size > 1
      results.first.filename
    end
    # http://localhost:60151/load?file=http://dbarchive.biosciencedbc.jp/kyushu-u/hg19/assembled/#{fname}&genome=hg19
    
    def filesearch(condition)
      self.where(:genome => condition["genome"])
        .where(:agClass => condition["agClass"])
        .where(:agSubClass => condition["agSubClass"])
        .where(:clClass => condition["clClass"])
        .where(:clSubClass => condition["clSubClass"])
        .where(:qval => condition["qval"])
    end
  end
end
