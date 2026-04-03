# frozen_string_literal: true

module ChipAtlas
  module ExperimentSearch
    COLUMNS = %w[exp_id sra_id geo_id genome ag_class ag_sub_class
                 cl_class cl_sub_class title attributes].freeze

    module_function

    def gsm_to_srx(gsm_id)
      row = DB["SELECT exp_id FROM experiments_fts WHERE geo_id = ?", gsm_id].first
      row&.[](:exp_id)
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
      experiments = rows.map { |row| ChipAtlas::Serializers.search_result(row) }

      { total: total, returned: experiments.size, experiments: experiments }
    end

    def load_from_json(json_data)
      rows = json_data['data']
      return if rows.nil? || rows.empty?

      DB.transaction do
        DB.run("DELETE FROM experiments_fts")

        rows.each_slice(500) do |batch|
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
