class Experiment < ActiveRecord::Base
end

class Bedfile < ActiveRecord::Base
  class << self
    def list_of_facets
      [ :agClass, :agSubClass, :clClass, :clSubClass, :qval ]
    end
    
    def list_of_genome
      self.all.map{|r| r.genome }.uniq
    end
    
    def records_by_genome(genome)
      self.where(:genome => genome)
    end
    
    def index_with_experiment_count(genome, column)
      records = records_by_genome(genome)
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

    def index_all_facets(genome)
      index = Hash.new
      list_of_facets.each do |facet|
        index[facet] = index_with_experiment_count(genome, facet)
      end
      index
    end
    
    def index_all_genome
      index = Hash.new
      list_of_genome.each do |genome|
        index[genome] = index_all_facets(genome)
      end
      index
    end
  end
end
