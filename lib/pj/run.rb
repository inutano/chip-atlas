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
        # Show file statistics
        file_stats = get_file_stats(table_path)
        puts "   File size: #{sprintf('%.1f', file_stats[:size_mb])} MB (#{file_stats[:total_lines]} lines)"

        # Get list of existing experiment IDs to filter by
        puts "   Getting existing experiment IDs for filtering..."
        existing_expids = PJ::Experiment.pluck(:expid).to_set
        puts "   Found #{existing_expids.size} experiment IDs in database"

        # Estimate efficiency gain
        estimate_filtered_size(existing_expids.size)

        # Use streaming approach to avoid loading entire file into memory
        puts "   Processing and filtering SRA run data (streaming)..."
        records = []
        timestamp = Time.current
        filtered_count = 0
        total_processed = 0
        batch_size = 50000  # Process in batches to manage memory

        # Stream through file using awk and process line by line
        IO.popen("awk -F '\t' '$8 == \"live\" { print $1 \"\\t\" $3 }' #{table_path}") do |pipe|
          pipe.each_line do |line|
            total_processed += 1

            # Progress indicator for large files
            if total_processed % 100000 == 0
              puts "   Processed #{total_processed} lines (#{filtered_count} matched, #{sprintf('%.1f', (filtered_count.to_f/total_processed)*100)}% pass rate)"
            end

            cols = line.chomp.split("\t")
            next if cols.size < 2

            runid = cols[0]
            expid = cols[1]

            # Only include runs for experiments that exist in our database
            if existing_expids.include?(expid)
              records << {
                runid: runid,
                expid: expid,
                timestamp: timestamp
              }
              filtered_count += 1

              # Insert in batches to manage memory usage
              if records.size >= batch_size
                puts "   Inserting batch of #{records.size} records..."
                self.insert_all(records, returning: false)
                records.clear
              end
            end
          end
        end

        # Insert remaining records
        if records.any?
          puts "   Inserting final batch of #{records.size} records..."
          self.insert_all(records, returning: false)
        end

        puts "   Summary: Filtered #{filtered_count} runs from #{total_processed} total runs"
        puts "   Filter efficiency: #{sprintf('%.2f', (1 - filtered_count.to_f/total_processed)*100)}% reduction"
      end

      def exp2run(exp_id)
        self.where(:expid => exp_id).map do |record|
          record.runid
        end
      end

      # Performance measurement helpers
      def get_file_stats(file_path)
        file_size_mb = File.size(file_path) / (1024.0 * 1024.0)
        total_lines = `wc -l < #{file_path}`.to_i
        {
          size_mb: file_size_mb,
          total_lines: total_lines
        }
      end

      def estimate_filtered_size(existing_expids_count, total_expids_estimate = 1000000)
        # Rough estimation of how much data will be filtered
        # This is a heuristic based on typical SRA data patterns
        filter_ratio = existing_expids_count.to_f / total_expids_estimate
        puts "   Estimated filter ratio: #{sprintf('%.2f', filter_ratio * 100)}%"
        filter_ratio
      end
    end
  end
end
