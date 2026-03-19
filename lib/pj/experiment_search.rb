require 'sinatra/activerecord'

module PJ
  module ExperimentSearch
    COLUMNS = %w[expid sra_id geo_id genome agClass agSubClass clClass clSubClass title attributes].freeze

    class << self
      def load_from_json(json_data)
        rows = json_data["data"]
        return if rows.nil? || rows.empty?

        db = ActiveRecord::Base.connection

        db.execute("DELETE FROM experiments_fts")

        # Bulk insert in batches using raw SQL to avoid AR type casting issues
        rows.each_slice(500) do |batch|
          values_sql = batch.map do |row|
            vals = COLUMNS.each_with_index.map do |_, i|
              v = row[i]
              v = v.join(", ") if v.is_a?(Array)
              "'" + (v || "").to_s.gsub("'", "''") + "'"
            end
            "(#{vals.join(', ')})"
          end.join(", ")

          db.execute(
            "INSERT INTO experiments_fts (#{COLUMNS.join(', ')}) VALUES #{values_sql}"
          )
        end

        puts "ExperimentSearch: loaded #{rows.size} rows into FTS5 table"
      end

      def search(query, genome: nil, limit: 20)
        return { total: 0, returned: 0, experiments: [] } if query.nil? || query.strip.empty?

        db = ActiveRecord::Base.connection

        # Escape special FTS5 characters and build match expression
        sanitized = fts5_sanitize(query)

        where_clause = "experiments_fts MATCH '#{sanitized.gsub("'", "''")}'"

        if genome && !genome.empty?
          where_clause += " AND genome = '#{genome.gsub("'", "''")}'"
        end

        # Count total matches
        count_sql = "SELECT COUNT(*) FROM experiments_fts WHERE #{where_clause}"
        total = db.execute(count_sql).first["COUNT(*)"].to_i

        # Fetch ranked results
        select_sql = <<-SQL
          SELECT expid, sra_id, geo_id, genome, agClass, agSubClass,
                 clClass, clSubClass, title, attributes,
                 rank
          FROM experiments_fts
          WHERE #{where_clause}
          ORDER BY rank
          LIMIT #{limit.to_i}
        SQL

        rows = db.execute(select_sql)

        experiments = rows.map do |row|
          {
            expid: row["expid"],
            sra_id: row["sra_id"],
            geo_id: row["geo_id"],
            genome: row["genome"],
            agClass: row["agClass"],
            agSubClass: row["agSubClass"],
            clClass: row["clClass"],
            clSubClass: row["clSubClass"],
            title: row["title"],
            attributes: row["attributes"]
          }
        end

        { total: total, returned: experiments.size, experiments: experiments }
      end

      private

      def fts5_sanitize(query)
        # Remove FTS5 special characters, then wrap each token in quotes for safety
        tokens = query.strip.split(/\s+/).map do |token|
          # Strip special FTS5 operators
          cleaned = token.gsub(/["'()*^{}:]/, "")
          next nil if cleaned.empty?
          %("#{cleaned}")
        end.compact

        tokens.join(" ")
      end
    end
  end
end
