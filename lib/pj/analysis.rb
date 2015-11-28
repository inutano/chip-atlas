require 'sinatra/activerecord'

module PJ
  class Analysis < ActiveRecord::Base
    class << self
      def load(table_path)
        open(table_path, "r:UTF-8").readlines.each do |line_n|
          line = line_n.chomp.split("\t")

          antigen      = line[0]
          cell_list    = line[1]
          target_genes = line[2] == "+"
          genome       = line[3]

          analysis = PJ::Analysis.new
          analysis.antigen      = antigen
          analysis.cell_list    = cell_list
          analysis.target_genes = target_genes
          analysis.genome       = genome
          analysis.save
        end
      end

      def results(type)
        case type
        when :colo
          colo_result
        when :target_genes
          target_genes_result
        end
      end

      def colo_result
        result = {}
        self.all.each do |record|
          genome    = record.genome
          antigen   = record.antigen
          cell_list = record.cell_list.split(",")
          next if cell_list.size == 0

          result[genome] ||= {}
          result[genome][:antigen] ||= {}
          result[genome][:antigen][antigen] = cell_list

          cell_list.each do |cl|
            result[genome][:cellline] ||= {}
            result[genome][:cellline][cl] ||= []
            result[genome][:cellline][cl] << antigen
          end
        end
        result
      end

      def target_genes_result
        result = {}
        self.all.each do |record|
          next if !record.target_genes
          genome    = record.genome
          result[genome] ||= []
          result[genome] << record.antigen
        end
        result
      end
    end
  end
end
