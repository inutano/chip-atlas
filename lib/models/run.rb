# frozen_string_literal: true

require 'shellwords'

module ChipAtlas
  module Run
    module_function

    def dataset
      DB[:runs]
    end

    def exp2run(exp_id)
      dataset.where(exp_id: exp_id).select_map(:run_id)
    end

    def load_from_file(table_path)
      existing_exp_ids = DB[:experiments].distinct.select_map(:exp_id).to_set
      warn "   Found #{existing_exp_ids.size} experiment IDs for filtering"

      records = []
      timestamp = Time.now
      filtered_count = 0
      total_processed = 0
      batch_size = 50_000

      IO.popen("awk -F '\t' '$8 == \"live\" { print $1 \"\\t\" $3 }' #{Shellwords.escape(table_path)}") do |pipe|
        pipe.each_line do |line|
          total_processed += 1

          if total_processed % 100_000 == 0
            warn "   Processed #{total_processed} lines (#{filtered_count} matched)"
          end

          cols = line.chomp.split("\t")
          next if cols.size < 2

          run_id, exp_id = cols[0], cols[1]

          if existing_exp_ids.include?(exp_id)
            records << { run_id: run_id, exp_id: exp_id, created_at: timestamp }
            filtered_count += 1

            if records.size >= batch_size
              warn "   Inserting batch of #{records.size} records..."
              dataset.multi_insert(records)
              records.clear
            end
          end
        end
      end

      dataset.multi_insert(records) if records.any?
      warn "   Summary: #{filtered_count} runs from #{total_processed} total"
      filtered_count
    end
  end
end
