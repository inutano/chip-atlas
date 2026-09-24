# frozen_string_literal: true

module ChipAtlas
  module ExperimentSearch
    COLUMNS = %w[experiment_id sra_id geo_id genome track_class track_subclass
                 cell_type_class cell_type_subclass title attributes].freeze

    # Track classes deliberately excluded from the search index.
    #
    # Annotation tracks are synthetic per-genome rows (gene models etc.), not
    # real sequencing experiments - nobody free-text searches for them, and
    # indexing them would surface ~500 hits that all look like duplicates of
    # each other. This used to be an accident: the `experiments` table loaded
    # from experimentList.tab (which includes them) while `experiments_fts`
    # loaded from a separate, stale ExperimentList_adv.json (which happened
    # not to). Now that both stores load from the same two files in the same
    # pass (see ChipAtlas::Experiment.load_from_files(table_path, json_path)),
    # the exclusion has to be written down explicitly - this is that rule.
    NOT_INDEXED_TRACK_CLASSES = ['Annotation tracks'].freeze

    module_function

    # Genome ids the loader will keep, read from config/genomes.yml via
    # ChipAtlas::Experiment (memoized there, not re-derived on every call).
    def supported_genomes
      ChipAtlas::Experiment.genomes.keys
    end

    # The experiments_fts table, for loaders/consistency checks that need
    # direct access (mirrors ChipAtlas::Experiment.dataset).
    def dataset
      DB[:experiments_fts]
    end

    # Whether a row with this track_class belongs in the search index.
    # See NOT_INDEXED_TRACK_CLASSES above for why Annotation tracks don't.
    def indexable?(track_class)
      !NOT_INDEXED_TRACK_CLASSES.include?(track_class)
    end

    # Every experiments_fts row is supposed to have a matching experiments
    # row (same experiment_id) - the search index must never point at a
    # dead /view link. Returns the number of rows that violate that.
    def orphaned_count
      DB[<<~SQL].first[:c]
        SELECT COUNT(*) AS c
        FROM experiments_fts f
        LEFT JOIN experiments e ON e.experiment_id = f.experiment_id
        WHERE e.experiment_id IS NULL
      SQL
    end

    # Post-load consistency gate. Called by lib/tasks/metadata.rake after a
    # fresh load; raises (failing the rake task loudly) instead of quietly
    # shipping search results that 404 on /view. See task-A3-report.md for
    # the 219-row orphan bug this closes.
    def assert_no_orphaned_fts_rows!
      orphans = orphaned_count
      return if orphans.zero?

      raise "experiments_fts has #{orphans} orphaned row(s) with no matching " \
            'experiments row - the search index is inconsistent with the experiments table'
    end

    # Memoized row counts for the blank-query listing path (list_all).
    # The total is a constant between data loads, so there is no need to pay
    # for a fresh COUNT(*) OVER() scan across all ~432k FTS5 rows (plus every
    # SELECTed column, materialized for the whole table before LIMIT/OFFSET
    # trims it down to 20) on every /search page load and every genome
    # change. Keyed by genome ("" for no filter); reset by
    # ChipAtlas::Experiment.load_from_files after each fresh load.
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

      sanitized = match_expression(query)
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

    MIN_PREFIX_LENGTH = 2

    # Turn a user query into an FTS5 MATCH expression.
    #   bare term of >= MIN_PREFIX_LENGTH chars -> "term"*   (prefix match)
    #   shorter term                            -> "term"    (exact; a 1-char
    #                                              prefix scans the whole index)
    #   "quoted phrase"                         -> "quoted phrase"*  (phrase prefix)
    # Every term stays inside double quotes, which is what keeps FTS5 operator
    # keywords (AND/OR/NOT/NEAR) and metacharacters from being parsed as syntax.
    def match_expression(query)
      terms = []
      query.to_s.strip.scan(/"([^"]*)"|(\S+)/) do |phrase, bare|
        cleaned = (phrase || bare).to_s.gsub(/["'()*^{}:]/, '').strip
        next if cleaned.empty?
        terms << (cleaned.length >= MIN_PREFIX_LENGTH ? %("#{cleaned}"*) : %("#{cleaned}"))
      end
      terms.join(' ')
    end
  end
end
