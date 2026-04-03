module ChipAtlas
  module ExperimentSearch
    COLUMNS = %w[exp_id sra_id geo_id genome ag_class ag_sub_class
                 cl_class cl_sub_class title attributes].freeze

    module_function

    def search(query, genome: nil, limit: 20, offset: 0)
      return { total: 0, returned: 0, experiments: [] } if query.nil? || query.strip.empty?

      sanitized = fts5_sanitize(query)
      return { total: 0, returned: 0, experiments: [] } if sanitized.empty?

      where_clause = "experiments_fts MATCH '#{sanitized.gsub("'", "''")}'"
      if genome && !genome.empty?
        where_clause += " AND genome = '#{genome.gsub("'", "''")}'"
      end

      total = DB["SELECT COUNT(*) AS c FROM experiments_fts WHERE #{where_clause}"]
                .first[:c]

      rows = DB[<<-SQL].all
        SELECT #{COLUMNS.join(', ')}, rank
        FROM experiments_fts
        WHERE #{where_clause}
        ORDER BY rank
        LIMIT #{limit.to_i}
        OFFSET #{offset.to_i}
      SQL

      # Sequel returns symbol keys; Serializers.search_result expects string keys
      experiments = rows.map do |row|
        string_row = row.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
        ChipAtlas::Serializers.search_result(string_row)
      end

      { total: total, returned: experiments.size, experiments: experiments }
    end

    def load_from_json(json_data)
      rows = json_data['data']
      return if rows.nil? || rows.empty?

      DB.run("DELETE FROM experiments_fts")

      rows.each_slice(500) do |batch|
        values_sql = batch.map do |row|
          vals = COLUMNS.each_with_index.map do |_, i|
            v = row[i]
            v = v.join(', ') if v.is_a?(Array)
            "'" + (v || '').to_s.gsub("'", "''") + "'"
          end
          "(#{vals.join(', ')})"
        end.join(', ')

        DB.run("INSERT INTO experiments_fts (#{COLUMNS.join(', ')}) VALUES #{values_sql}")
      end

      puts "ExperimentSearch: loaded #{rows.size} rows into FTS5 table"
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
