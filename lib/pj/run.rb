require 'sinatra/activerecord'

module PJ
  class Run < ActiveRecord::Base
    class << self
      def fetch(dest_fname)
        base  = "ftp.ncbi.nlm.nih.gov/sra/reports/Metadata"
        fname = "SRA_Run_Members.tab"
        dest_dir = File.dirname(dest_fname)
        `lftp -c "open #{base} && pget -n 8 -O #{dest_dir} #{fname}"`
      end

      def load(table_path)
        list = `cat #{table_path} | awk -F '\t' '$8 == "live" { print $1 "\t" $3 }'`.split("\n")
        records = []
        timestamp = Time.current

        list.each do |line|
          cols = line.split("\t")
          records << {
            runid: cols[0],
            expid: cols[1],
            timestamp: timestamp
          }
        end

        self.insert_all(records) if records.any?
      end

      def exp2run(exp_id)
        self.where(:expid => exp_id).map do |record|
          record.runid
        end
      end
    end
  end
end
