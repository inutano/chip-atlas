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
        list.each do |line|
          cols = line.split("\t")
          run_id = cols[0]
          exp_id = cols[1]

          run = self.new
          run.runid = run_id
          run.expid = exp_id
          run.save
        end
      end

      def exp2run(exp_id)
        self.where(:expid => exp_id).map do |record|
          record.runid
        end
      end
    end
  end
end
