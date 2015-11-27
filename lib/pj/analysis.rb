require 'sinatra/activerecord'

module PJ
  class Analysis < ActiveRecord::Base
    class << self
      def load(table_path)
        open(table_path, "r:UTF-8").readlines.each do |line_n|
          line = line_n.chomp.split("\t")

          antigen      = line[0]
          cell_list    = line[1]
          target_genes = if line[2] == "+"
          genome       = line[3]

          analysis = PJ::Analysis.new
          analysis.antigen      = antigen
          analysis.cell_list    = cell_list
          analysis.target_genes = target_genes
          analysis.genome       = genome
          analysis.save
        end
      end
    end
  end
end
