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

    def experiment_types(genome, cl_class)
      subset = dataset.where(genome: genome)
      subset = subset.where(cl_class: cl_class) unless cl_class == 'All cell types'
      counts = subset.group_and_count(:ag_class).as_hash(:ag_class, :count)

      EXPERIMENT_TYPES.map do |t|
        { id: t[:id], label: t[:label], count: counts[t[:id]] }
      end
    end

    def sample_types(genome, ag_class)
      ag_class = EXPERIMENT_TYPES.first[:id] if ag_class == 'undefined'

      groups = dataset.where(genome: genome, ag_class: ag_class)
                      .group_and_count(:cl_class)

      total = 0
      result = []
      groups.each do |row|
        result << { id: row[:cl_class], label: row[:cl_class], count: row[:count] }
        total += row[:count]
      end

      result.unshift({ id: 'All cell types', label: 'All cell types', count: total })
      result
    end

    def chip_antigen(genome, ag_class, cl_class)
      ag_class = EXPERIMENT_TYPES.first[:id] if ag_class == 'undefined'
      result = [{ id: '-', label: 'All', count: nil }]

      subset = dataset.where(genome: genome, ag_class: ag_class)
      unless cl_class == 'undefined' || cl_class == 'All cell types'
        subset = subset.where(cl_class: cl_class)
      end

      subset.group_and_count(:ag_sub_class).each do |row|
        result << { id: row[:ag_sub_class], label: row[:ag_sub_class], count: row[:count] }
      end
      result
    end

    def cell_type(genome, ag_class, cl_class)
      result = [{ id: '-', label: 'All', count: nil }]

      if cl_class != 'undefined' && cl_class != 'All cell types'
        ag_class = EXPERIMENT_TYPES.first[:id] if ag_class == 'undefined'
        subset = dataset.where(genome: genome, ag_class: ag_class, cl_class: cl_class)
        subset.group_and_count(:cl_sub_class).each do |row|
          result << { id: row[:cl_sub_class], label: row[:cl_sub_class], count: row[:count] }
        end
      end
      result
    end

    def record_by_exp_id(exp_id)
      dataset.where(exp_id: exp_id)
        .select(:exp_id, :genome, :ag_class, :ag_sub_class, :cl_class, :cl_sub_class,
                :title, :attributes, :read_info, :cl_sub_class_info)
        .all
        .sort_by { |r| GENOME_ORDER.fetch(r[:genome], 999) }
    end

    def id_valid?(exp_id)
      !dataset.where(exp_id: exp_id).empty?
    end

    def number_of_experiments
      dataset.distinct.select(:exp_id).count
    end

    def total_number_of_reads(ids)
      return 0 if ids.nil? || ids.empty?

      placeholders = ids.map { '?' }.join(', ')
      sql = "SELECT COALESCE(SUM(CAST(SUBSTR(read_info, 1, INSTR(read_info, ',') - 1) AS INTEGER)), 0) AS total FROM experiments WHERE exp_id IN (#{placeholders})"
      DB[sql, *ids].first[:total]
    end

    def index_all_genome
      result = {}
      GENOMES.each_key { |g| result[g] = { antigen: {}, celltype: {} } }

      # One query for all antigen counts across all genomes
      dataset.group_and_count(:genome, :ag_class, :ag_sub_class).each do |row|
        g = row[:genome]
        next unless result.key?(g)
        result[g][:antigen][row[:ag_class]] ||= Hash.new(0)
        result[g][:antigen][row[:ag_class]][row[:ag_sub_class]] = row[:count]
      end

      # One query for all celltype counts across all genomes
      dataset.group_and_count(:genome, :cl_class, :cl_sub_class).each do |row|
        g = row[:genome]
        next unless result.key?(g)
        result[g][:celltype][row[:cl_class]] ||= Hash.new(0)
        result[g][:celltype][row[:cl_class]][row[:cl_sub_class]] = row[:count]
      end

      result
    end

    def get_subclass(genome, ag_class, cl_class, subclass_type)
      ag_eval = ag_class == 'All antigens' && subclass_type == 'ag'
      cl_eval = cl_class == 'All cell types' && subclass_type == 'cl'
      return {} if ag_eval || cl_eval

      subset = dataset.where(genome: genome)
      subset = subset.where(ag_class: ag_class) unless ag_class == 'All antigens'
      subset = subset.where(cl_class: cl_class) unless cl_class == 'All cell types'

      col = subclass_type == 'ag' ? :ag_sub_class : :cl_sub_class
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
          records << {
            exp_id:            cols[0],
            genome:            cols[1],
            ag_class:          cols[2],
            ag_sub_class:      cols[3],
            cl_class:          cols[4],
            cl_sub_class:      cols[5],
            cl_sub_class_info: cols[6],
            read_info:         cols[7],
            title:             cols[8],
            attributes:        cols[9..].to_a.join("\t"),
            created_at:        timestamp,
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
