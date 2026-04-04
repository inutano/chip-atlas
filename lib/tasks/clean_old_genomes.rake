# frozen_string_literal: true

namespace :db do
  desc "Remove rows for old/unsupported genome assemblies and rebuild FTS index"
  task :clean_old_genomes do
    OLD_GENOMES = %w[hg19 mm9 dm3 ce10].freeze
    SUPPORTED_GENOMES = %w[hg38 mm10 rn6 dm6 ce11 sacCer3 TAIR10].freeze
    FTS_COLUMNS = %w[experiment_id sra_id geo_id genome track_class track_subclass
                     cell_type_class cell_type_subclass title attributes].freeze

    tables = %i[experiments bedfiles bedsizes analyses]

    puts "=== Cleaning old genome assemblies ==="
    puts "Old genomes to remove: #{OLD_GENOMES.join(', ')}"
    puts "Supported genomes:     #{SUPPORTED_GENOMES.join(', ')}"
    puts

    # Report counts before cleaning
    puts "--- Row counts BEFORE cleaning ---"
    tables.each do |table|
      total = DB[table].count
      old_count = DB[table].where(genome: OLD_GENOMES).count
      puts "  #{table}: #{total} total, #{old_count} with old genomes"
    end
    fts_total_before = DB["SELECT COUNT(*) AS c FROM experiments_fts"].first[:c]
    puts "  experiments_fts: #{fts_total_before} total"
    puts

    # Delete old-genome rows from regular tables inside a transaction
    DB.transaction do
      tables.each do |table|
        deleted = DB[table].where(genome: OLD_GENOMES).delete
        puts "Deleted #{deleted} rows from #{table}"
      end
    end
    puts

    # Rebuild FTS index: read all rows, filter genome strings, re-insert
    puts "Rebuilding experiments_fts index..."
    all_fts_rows = DB["SELECT #{FTS_COLUMNS.join(', ')} FROM experiments_fts"].all

    cleaned_rows = []
    dropped = 0

    all_fts_rows.each do |row|
      genome_value = row[:genome].to_s
      # The genome field may contain comma-separated genomes like "hg19, hg38"
      genomes = genome_value.split(/,\s*/).map(&:strip).reject(&:empty?)
      kept = genomes.select { |g| SUPPORTED_GENOMES.include?(g) }

      if kept.empty?
        dropped += 1
        next
      end

      row[:genome] = kept.first
      cleaned_rows << row
    end

    puts "  FTS rows read: #{all_fts_rows.size}"
    puts "  FTS rows kept: #{cleaned_rows.size}"
    puts "  FTS rows dropped: #{dropped}"

    DB.transaction do
      DB.run("DELETE FROM experiments_fts")

      cleaned_rows.each_slice(500) do |batch|
        values_sql = batch.map do |row|
          vals = FTS_COLUMNS.map do |col|
            DB.literal((row[col.to_sym] || '').to_s)
          end
          "(#{vals.join(', ')})"
        end.join(', ')

        DB.run("INSERT INTO experiments_fts (#{FTS_COLUMNS.join(', ')}) VALUES #{values_sql}")
      end
    end
    puts

    # Report counts after cleaning
    puts "--- Row counts AFTER cleaning ---"
    tables.each do |table|
      puts "  #{table}: #{DB[table].count}"
    end
    fts_total_after = DB["SELECT COUNT(*) AS c FROM experiments_fts"].first[:c]
    puts "  experiments_fts: #{fts_total_after}"
    puts

    # VACUUM must run outside a transaction
    puts "Running VACUUM to reclaim disk space..."
    DB.run("VACUUM")
    puts "VACUUM complete."
    puts
    puts "=== Done ==="
  end
end
