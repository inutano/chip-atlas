# frozen_string_literal: true

module ChipAtlas
  module Analysis
    TARGET_GENES_DISTANCES = [
      { id: '1', label: '1 kb' },
      { id: '5', label: '5 kb' },
      { id: '10', label: '10 kb' },
    ].freeze

    # TODO(B4): once the colo index build exists, replace this explicit
    # allowlist with a check derived from which genomes actually have a colo
    # index (the archive has no `colo/` directory at all under TAIR12 today,
    # and there is no reliable signal for "has colo data" in this table yet —
    # see task A2's report for why an allowlist was used instead of deriving
    # this from the `analyses` table).
    GENOMES_WITH_COLO = %w[hg38 mm10 rn6 dm6 ce11 sacCer3].freeze

    module_function

    def target_genes_distances
      TARGET_GENES_DISTANCES
    end

    # Genome tab strip for /colo: the full registry, filtered down to genomes
    # known to have colocalization data. Preserves config/genomes.yml order.
    def genomes_with_colo
      ChipAtlas::Experiment.genomes.select { |id, _| GENOMES_WITH_COLO.include?(id) }
    end

    def dataset
      DB[:analyses]
    end

    def colo_result_by_genome(genome)
      result = { genome => { track: {}, cell_type: {} } }

      dataset.where(genome: genome).each do |row|
        cell_list = row[:cell_list].to_s.split(',')
        next if cell_list.empty?

        track = row[:track]
        result[genome][:track][track] = cell_list

        cell_list.each do |cl|
          result[genome][:cell_type][cl] ||= []
          result[genome][:cell_type][cl] << track
        end
      end
      result
    end

    def target_genes_result
      result = {}
      dataset.where(target_genes: true).each do |row|
        genome = row[:genome]
        result[genome] ||= []
        result[genome] << row[:track]
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
          genome = cols[3]
          next unless ChipAtlas::Experiment.genomes.key?(genome)

          records << {
            track:        cols[0],
            cell_list:    cols[1],
            target_genes: cols[2] == '+',
            genome:       genome,
            created_at:   timestamp,
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
