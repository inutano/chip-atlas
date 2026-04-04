# frozen_string_literal: true

module ChipAtlas
  module Experiment
    GENOMES = {
      'hg38'    => 'H. sapiens (hg38)',
      'mm10'    => 'M. musculus (mm10)',
      'rn6'     => 'R. norvegicus (rn6)',
      'dm6'     => 'D. melanogaster (dm6)',
      'ce11'    => 'C. elegans (ce11)',
      'sacCer3' => 'S. cerevisiae (sacCer3)',
      'TAIR10'  => 'A. thaliana (TAIR10)',
    }.freeze

    GENOME_ORDER = GENOMES.keys.each_with_index.to_h.freeze

    EXPERIMENT_TYPES = [
      { id: 'Histone',          label: 'ChIP: Histone' },
      { id: 'RNA polymerase',   label: 'ChIP: RNA polymerase' },
      { id: 'TFs and others',   label: 'ChIP: TFs and others' },
      { id: 'Input control',    label: 'ChIP: Input control' },
      { id: 'ATAC-Seq',         label: 'ATAC-Seq' },
      { id: 'DNase-seq',        label: 'DNase-seq' },
      { id: 'Bisulfite-Seq',    label: 'Bisulfite-Seq' },
      { id: 'CUT&Tag',          label: 'CUT&Tag' },
      { id: 'CUT&RUN',          label: 'CUT&RUN' },
      { id: 'Annotation tracks', label: 'Annotation tracks' },
    ].freeze

    @index_cache = nil
    @index_cache_at = nil
    INDEX_CACHE_TTL = 3600  # 1 hour

    module_function

    def formatted_experiment_count
      count = number_of_experiments
      rounded = (count / 1000) * 1000
      rounded.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')
    end

    def stats
      genomes = {}
      dataset.group_and_count(:genome).each do |row|
        genomes[row[:genome]] = row[:count]
      end

      track_classes = {}
      dataset.group_and_count(:track_class).each do |row|
        track_classes[row[:track_class]] = row[:count]
      end

      {
        total_experiments: number_of_experiments,
        total_experiments_formatted: formatted_experiment_count,
        by_genome: genomes,
        by_track_class: track_classes,
      }
    end

    def cached_index_all_genome
      now = Time.now
      if @index_cache && @index_cache_at && (now - @index_cache_at) < INDEX_CACHE_TTL
        return @index_cache
      end

      @index_cache = index_all_genome
      @index_cache_at = now
      @index_cache
    end

    def dataset
      DB[:experiments]
    end

    def list_of_genome
      GENOMES
    end

    def list_of_experiment_types
      EXPERIMENT_TYPES
    end

    def experiment_types(genome, cell_type_class)
      subset = dataset.where(genome: genome)
      subset = subset.where(cell_type_class: cell_type_class) unless cell_type_class == 'All cell types'
      counts = subset.group_and_count(:track_class).as_hash(:track_class, :count)

      EXPERIMENT_TYPES.map do |t|
        { id: t[:id], label: t[:label], count: counts[t[:id]] }
      end
    end

    def sample_types(genome, track_class)
      track_class = EXPERIMENT_TYPES.first[:id] if track_class == 'undefined'

      groups = dataset.where(genome: genome, track_class: track_class)
                      .group_and_count(:cell_type_class)

      total = 0
      result = []
      groups.each do |row|
        result << { id: row[:cell_type_class], label: row[:cell_type_class], count: row[:count] }
        total += row[:count]
      end

      result.unshift({ id: 'All cell types', label: 'All cell types', count: total })
      result
    end

    def chip_antigen(genome, track_class, cell_type_class)
      track_class = EXPERIMENT_TYPES.first[:id] if track_class == 'undefined'
      result = [{ id: '-', label: 'All', count: nil }]

      subset = dataset.where(genome: genome, track_class: track_class)
      unless cell_type_class == 'undefined' || cell_type_class == 'All cell types'
        subset = subset.where(cell_type_class: cell_type_class)
      end

      subset.group_and_count(:track_subclass).each do |row|
        result << { id: row[:track_subclass], label: row[:track_subclass], count: row[:count] }
      end
      result
    end

    def cell_type(genome, track_class, cell_type_class)
      result = [{ id: '-', label: 'All', count: nil }]

      if cell_type_class != 'undefined' && cell_type_class != 'All cell types'
        track_class = EXPERIMENT_TYPES.first[:id] if track_class == 'undefined'
        subset = dataset.where(genome: genome, track_class: track_class, cell_type_class: cell_type_class)
        subset.group_and_count(:cell_type_subclass).each do |row|
          result << { id: row[:cell_type_subclass], label: row[:cell_type_subclass], count: row[:count] }
        end
      end
      result
    end

    def record_by_experiment_id(experiment_id)
      dataset.where(experiment_id: experiment_id)
        .select(:experiment_id, :genome, :track_class, :track_subclass, :cell_type_class, :cell_type_subclass,
                :title, :attributes, :read_info, :cell_type_subclass_info)
        .all
        .sort_by { |r| GENOME_ORDER.fetch(r[:genome], 999) }
    end

    def id_valid?(experiment_id)
      !dataset.where(experiment_id: experiment_id).empty?
    end

    def number_of_experiments
      dataset.distinct.select(:experiment_id).count
    end

    def total_number_of_reads(ids)
      return 0 if ids.nil? || ids.empty?

      placeholders = ids.map { '?' }.join(', ')
      sql = "SELECT COALESCE(SUM(CAST(SUBSTR(read_info, 1, INSTR(read_info, ',') - 1) AS INTEGER)), 0) AS total FROM experiments WHERE experiment_id IN (#{placeholders})"
      DB[sql, *ids].first[:total]
    end

    def index_all_genome
      result = {}
      GENOMES.each_key { |g| result[g] = { track: {}, cell_type: {} } }

      # One query for all track counts across all genomes
      dataset.group_and_count(:genome, :track_class, :track_subclass).each do |row|
        g = row[:genome]
        next unless result.key?(g)
        result[g][:track][row[:track_class]] ||= Hash.new(0)
        result[g][:track][row[:track_class]][row[:track_subclass]] = row[:count]
      end

      # One query for all cell_type counts across all genomes
      dataset.group_and_count(:genome, :cell_type_class, :cell_type_subclass).each do |row|
        g = row[:genome]
        next unless result.key?(g)
        result[g][:cell_type][row[:cell_type_class]] ||= Hash.new(0)
        result[g][:cell_type][row[:cell_type_class]][row[:cell_type_subclass]] = row[:count]
      end

      result
    end

    def get_subclass(genome, track_class, cell_type_class, subclass_type)
      ag_eval = track_class == 'All antigens' && subclass_type == 'ag'
      cl_eval = cell_type_class == 'All cell types' && subclass_type == 'cl'
      return {} if ag_eval || cl_eval

      subset = dataset.where(genome: genome)
      subset = subset.where(track_class: track_class) unless track_class == 'All antigens'
      subset = subset.where(cell_type_class: cell_type_class) unless cell_type_class == 'All cell types'

      col = subclass_type == 'ag' ? :track_subclass : :cell_type_subclass
      subset.group_and_count(col).as_hash(col, :count)
    end

    def load_from_file(table_path)
      timestamp = Time.now
      total = 0
      batch_size = 5_000

      DB.transaction do
        records = []

        File.foreach(table_path, encoding: 'UTF-8') do |line_n|
          cols = line_n.chomp.split("\t")
          genome = cols[1]
          next unless GENOMES.key?(genome)

          records << {
            experiment_id:                 cols[0],
            genome:                 cols[1],
            track_class:            cols[2],
            track_subclass:         cols[3],
            cell_type_class:        cols[4],
            cell_type_subclass:     cols[5],
            cell_type_subclass_info: cols[6],
            read_info:              cols[7],
            title:                  cols[8],
            attributes:             cols[9..].to_a.join("\t"),
            created_at:             timestamp,
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
