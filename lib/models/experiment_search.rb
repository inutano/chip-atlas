# frozen_string_literal: true

module ChipAtlas
  module ExperimentSearch
    COLUMNS = %w[experiment_id sra_id geo_id genome track_class track_subclass
                 cell_type_class cell_type_subclass title attributes].freeze

    SUPPORTED_GENOMES = ChipAtlas::Experiment::GENOMES.keys.freeze

    module_function

    def gsm_to_srx(gsm_id)
      row = DB["SELECT experiment_id FROM experiments_fts WHERE geo_id = ?", gsm_id].first
      row&.[](:experiment_id)
    end

    def search(query, genome: nil, limit: 20, offset: 0)
      return { total: 0, returned: 0, experiments: [] } if query.nil? || query.strip.empty?

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

    def load_from_json(json_data)
      rows = json_data['data']
      return if rows.nil? || rows.empty?

      DB.transaction do
        DB.run("DELETE FROM experiments_fts")

        rows.each_slice(500) do |batch|
          batch = batch.reject do |row|
            genomes = row[3]
            if genomes.is_a?(Array)
              genomes = genomes.select { |g| SUPPORTED_GENOMES.include?(g) }
              row[3] = genomes.first  # store single genome
              genomes.empty?
            else
              !SUPPORTED_GENOMES.include?(genomes.to_s)
            end
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
