# frozen_string_literal: true

module ChipAtlas
  module ExperimentSearch
    COLUMNS = %w[experiment_id sra_id geo_id genome track_class track_subclass
                 cell_type_class cell_type_subclass title attributes].freeze

    module_function

    # Genome ids the FTS5 loader will keep, read from config/genomes.yml via
    # ChipAtlas::Experiment (memoized there, not re-derived on every call).
    def supported_genomes
      ChipAtlas::Experiment.genomes.keys
    end

    # Memoized row counts for the blank-query listing path (list_all).
    # The total is a constant between data loads, so there is no need to pay
    # for a fresh COUNT(*) OVER() scan across all ~432k FTS5 rows (plus every
    # SELECTed column, materialized for the whole table before LIMIT/OFFSET
    # trims it down to 20) on every /search page load and every genome
    # change. Keyed by genome ("" for no filter); reset on load_from_json.
    def total_count_cache
      @total_count_cache ||= {}
    end

    def reset_total_count_cache!
      @total_count_cache = {}
    end

    def total_count(genome = nil)
      key = (genome && !genome.empty?) ? genome : ''
      total_count_cache[key] ||= if key.empty?
        DB["SELECT COUNT(*) AS c FROM experiments_fts"].first[:c]
      else
        DB["SELECT COUNT(*) AS c FROM experiments_fts WHERE genome = ?", key].first[:c]
      end
    end

    def gsm_to_srx(gsm_id)
      row = DB["SELECT experiment_id FROM experiments_fts WHERE geo_id = ?", gsm_id].first
      row&.[](:experiment_id)
    end

    def search(query, genome: nil, limit: 20, offset: 0)
      return list_all(genome: genome, limit: limit, offset: offset) if query.nil? || query.strip.empty?

      sanitized = fts5_sanitize(query)
      return { total: 0, returned: 0, experiments: [] } if sanitized.empty?

      if genome && !genome.empty?
        sql = <<~SQL
          SELECT #{COLUMNS.join(', ')}, rank, COUNT(*) OVER() AS total_count
          FROM experiments_fts
          WHERE experiments_fts MATCH ? AND genome = ?
          ORDER BY rank
          LIMIT ? OFFSET ?
        SQL
        rows = DB[sql, sanitized, genome, limit.to_i, offset.to_i].all
      else
        sql = <<~SQL
          SELECT #{COLUMNS.join(', ')}, rank, COUNT(*) OVER() AS total_count
          FROM experiments_fts
          WHERE experiments_fts MATCH ?
          ORDER BY rank
          LIMIT ? OFFSET ?
        SQL
        rows = DB[sql, sanitized, limit.to_i, offset.to_i].all
      end

      total = rows.first&.[](:total_count) || 0
      experiments = rows.map { |row| row.except(:rank, :total_count) }

      { total: total, returned: experiments.size, experiments: experiments }
    end

    def list_all(genome: nil, limit: 20, offset: 0)
      total = total_count(genome)
      if genome && !genome.empty?
        sql = <<~SQL
          SELECT #{COLUMNS.join(', ')}
          FROM experiments_fts
          WHERE genome = ?
          ORDER BY experiment_id
          LIMIT ? OFFSET ?
        SQL
        rows = DB[sql, genome, limit.to_i, offset.to_i].all
      else
        sql = <<~SQL
          SELECT #{COLUMNS.join(', ')}
          FROM experiments_fts
          ORDER BY experiment_id
          LIMIT ? OFFSET ?
        SQL
        rows = DB[sql, limit.to_i, offset.to_i].all
      end

      { total: total, returned: rows.size, experiments: rows }
    end

    def load_from_json(json_data)
      rows = json_data['data']
      return if rows.nil? || rows.empty?

      DB.transaction do
        DB.run("DELETE FROM experiments_fts")

        rows.each_slice(500) do |batch|
          batch = batch.reject do |row|
            # The genome field may be an array or a comma-separated string like "hg19, hg38"
            genomes = row[3]
            genomes = genomes.to_s.split(/,\s*/) unless genomes.is_a?(Array)
            kept = genomes.map(&:strip).reject(&:empty?).select { |g| supported_genomes.include?(g) }
            row[3] = kept.first  # store single genome
            kept.empty?
          end
          next if batch.empty?

          values_sql = batch.map do |row|
            vals = COLUMNS.each_with_index.map do |_, i|
              v = row[i]
              v = v.join(', ') if v.is_a?(Array)
              DB.literal((v || '').to_s)
            end
            "(#{vals.join(', ')})"
          end.join(', ')

          DB.run("INSERT INTO experiments_fts (#{COLUMNS.join(', ')}) VALUES #{values_sql}")
        end
      end

      reset_total_count_cache!
      warn "ExperimentSearch: loaded #{rows.size} rows into FTS5 table"
    end

    def fts5_sanitize(query)
      tokens = query.strip.split(/\s+/).map do |token|
        cleaned = token.gsub(/["'()*^{}:]/, '')
        next nil if cleaned.empty?
        "\"#{cleaned}\""
      end.compact
      tokens.join(' ')
    end

    private_class_method :fts5_sanitize
  end
end
