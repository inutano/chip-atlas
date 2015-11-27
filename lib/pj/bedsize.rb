require 'sinatra/activerecord'

module PJ
  class Bedsize < ActiveRecord::Base
    class << self
      def load(table_path)
        open(table_path, "r:UTF-8").readlines.each do |line_n|
          line = line_n.chomp.split("\t")

          genome   = line[0]
          ag_class = line[1]
          cl_class = line[2]
          qval     = line[3]
          number_of_lines = line[4]

          bedsize = PJ::Bedsize.new
          bedsize.genome  = genome
          bedsize.agClass = ag_class
          bedsize.clClass = cl_class
          bedsize.qval    = qval
          bedsize.number_of_lines = number_of_lines
          bedsize.save
        end
      end
    end
  end
end
