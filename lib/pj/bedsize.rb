require 'sinatra/activerecord'

module PJ
  class Bedsize < ActiveRecord::Base
    class << self
      def load(table_path)
        records = []
        timestamp = Time.current

        File.foreach(table_path, encoding: "UTF-8") do |line_n|
          line = line_n.chomp.split("\t")
          records << {
            genome: line[0],
            agClass: line[1],
            clClass: line[2],
            qval: line[3],
            number_of_lines: line[4],
            timestamp: timestamp
          }
        end

        self.insert_all(records, returning: false) if records.any?
      end

      def dump
        result = {}
        self.all.each do |record|
          fname = [record.genome, record.agClass, record.clClass, record.qval].join(",")
          result[fname] = record.number_of_lines
        end
        result
      end
    end
  end
end
