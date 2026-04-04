# frozen_string_literal: true

module ChipAtlas
  module Bedfile
    NotFound = Class.new(StandardError)

    module_function

    def dataset
      DB[:bedfiles]
    end

    def get_filename(condition)
      results = filesearch(condition)
      raise NotFound, "No bedfile found for condition" if results.empty?
      raise NotFound, "Multiple bedfiles found" if results.size > 1
      results.first[:filename]
    end

    def get_trackname(condition)
      results = filesearch(condition)
      raise NotFound if results.size != 1
      results.first[:track_subclass]
    end

    def filesearch(condition)
      dataset
        .where(genome: condition[:genome])
        .where(track_class: condition[:track_class])
        .where(track_subclass: condition[:track_subclass] || '-')
        .where(cell_type_class: condition[:cell_type_class])
        .where(cell_type_subclass: condition[:cell_type_subclass] || '-')
        .where(qval: condition[:qval])
        .limit(2)
        .all
    end

    def qval_range
      dataset
        .exclude(track_class: 'Bisulfite-Seq')
        .exclude(track_class: 'Annotation tracks')
        .distinct
        .select_map(:qval)
        .compact
        .sort
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
            filename:           cols[0],
            genome:             cols[1],
            track_class:        cols[2],
            track_subclass:     cols[3],
            cell_type_class:    cols[4],
            cell_type_subclass: cols[5],
            qval:               cols[6],
            experiments:        cols[7],
            created_at:         timestamp,
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

    private_class_method :filesearch
  end
end
