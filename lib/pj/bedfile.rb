require 'sinatra/activerecord'

module PJ
  class Bedfile < ActiveRecord::Base
    class << self
      def load(table_path)
        records = []
        timestamp = Time.current

        File.foreach(table_path, encoding: "UTF-8") do |line_n|
          line = line_n.chomp.split("\t")
          records << {
            filename: line[0],
            genome: line[1],
            agClass: line[2],
            agSubClass: line[3],
            clClass: line[4],
            clSubClass: line[5],
            qval: line[6],
            experiments: line[7],
            timestamp: timestamp
          }
        end

        self.insert_all(records, returning: false) if records.any?
      end

      #
      # Retrieve filename from search condition
      #

      def get_filename(condition)
        results = filesearch(condition)
        raise NameError if results.size != 1
        results.first.filename
      end

      def get_trackname(condition)
        results = filesearch(condition)
        raise NameError if results.size != 1
        results.first.agSubClass
      end

      def filesearch(condition)
        self.where(:genome => condition["genome"])
          .where(:agClass => condition["agClass"])
          .where(:agSubClass => condition["agSubClass"] || "-")
          .where(:clClass => condition["clClass"])
          .where(:clSubClass => condition["clSubClass"] || "-")
          .where(:qval => condition["qval"])
      end

      def list_of_facets
        [ :agClass, :agSubClass, :clClass, :clSubClass, :qval ]
      end

      def qval_range
        self.where.not(agClass: 'Bisulfite-Seq').where.not(agClass: 'Annotation tracks').map{|r| r.qval }.uniq.sort
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

      def records_by_genome(genome)
        self.where(:genome => genome)
      end

      def index_by_genome(genome)
        records = records_by_genome(genome)
        index_all_facets(records)
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

    end
  end
end
