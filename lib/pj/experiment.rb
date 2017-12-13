require 'sinatra/activerecord'

module PJ
  class Experiment < ActiveRecord::Base
    class << self
      def load(table_path)
        open(table_path, "r:UTF-8").readlines.each do |line_n|
          line = line_n.chomp.split("\t")
          expid            = line[0]
          genome           = line[1]
          ag_class         = line[2]
          ag_subclass      = line[3]
          cl_class         = line[4]
          cl_subclass      = line[5]
          cl_subclass_info = line[6]
          read_info        = line[7]
          title            = line[8]
          additional_attributes = line[9..line.size].join("\t")

          exp = PJ::Experiment.new
          exp.expid      = expid
          exp.genome     = genome
          exp.agClass    = ag_class
          exp.agSubClass = ag_subclass
          exp.clClass    = cl_class
          exp.clSubClass = cl_subclass
          exp.clSubClassInfo = cl_subclass_info
          exp.readInfo   = read_info
          exp.title      = title
          exp.additional_attributes = additional_attributes
          exp.save
        end
      end

      def id_valid?(exp_id)
        !self.where(:expid => exp_id).empty?
      end

      def record_by_expid(exp_id)
        records = self.where(:expid => exp_id)
        raise NameError if records.size > 1
        record = records.first
        {
          :expid      => exp_id,
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

      def list_of_facets
        [ :agClass, :agSubClass, :clClass, :clSubClass ]
      end

      def list_of_genome
        [ "hg19", "mm9", "rn6", "dm3", "ce10", "sacCer3", ]
        # self.all.map{|r| r.genome }.uniq
      end

      ## Retrieve sub class options
      def get_subclass(genome, ag_class, cl_class, subclass_type)
        f_genome = self.where(:genome => genome)
        ag_eval = ag_class == "All antigens" && subclass_type == "ag"
        cl_eval = cl_class == "All cell types" && subclass_type == "cl"
        if ag_eval || cl_eval
          {}
        else
          f_ag     = ag_class == "All antigens" ? f_genome : f_genome.where(:agClass => ag_class)
          f_cl     = cl_class == "All cell types" ? f_ag : f_ag.where(:clClass => cl_class)
          h = { "ag" => :agSubClass, "cl" => :clSubClass }
          filtered = f_cl.map{|r| r.send(h[subclass_type]) }
          index = {}
          filtered.each do |subclass|
            index[subclass] ||= 0
            index[subclass] += 1
          end
          index
        end
      end

      ## Methods to display facets
      def records_by_genome(genome)
        self.where(:genome => genome)
      end

      def index_by_genome(genome)
        records = records_by_genome(genome)
        index_all_facets(records)
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

      def empty_index
        {
          antigen: {},
          celltype: {}
        }
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
    end
  end
end
