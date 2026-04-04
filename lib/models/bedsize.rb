# frozen_string_literal: true

module ChipAtlas
  module Bedsize
    module_function

    def dataset
      DB[:bedsizes]
    end

    def dump
      result = {}
      dataset.each do |row|
        key = [row[:genome], row[:track_class], row[:cell_type_class], row[:qval]].join(',')
        result[key] = row[:number_of_lines]
      end
      result
    end

    def load_from_file(table_path)
      timestamp = Time.now
      total = 0
      batch_size = 5_000

      DB.transaction do
        records = []

        File.foreach(table_path, encoding: 'UTF-8') do |line_n|
          cols = line_n.chomp.split("\t")
          records << {
            genome:           cols[0],
            track_class:      cols[1],
            cell_type_class:  cols[2],
            qval:             cols[3],
            number_of_lines:  cols[4].to_i,
            created_at:       timestamp,
          }

          if records.size >= batch_size
            dataset.multi_insert(records)
            total += records.size
            records.clear
          end
        end

        if records.any?
          dataset.multi_insert(records)
          total += records.size
        end
      end
      total
    end
  end
end
