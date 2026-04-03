# frozen_string_literal: true

require 'sequel'

unless defined?(DB)
  ENV['DATABASE_URL'] ||= "sqlite://database.sqlite"
  DB = Sequel.connect(ENV['DATABASE_URL'], pool_timeout: 300)
  begin
    DB.run("PRAGMA journal_mode=WAL")
    DB.run("PRAGMA synchronous=NORMAL")
    DB.run("PRAGMA cache_size=-64000")  # 64MB cache
    DB.run("PRAGMA mmap_size=268435456")  # 256MB memory-mapped I/O
  rescue Sequel::DatabaseError
    # PRAGMAs not supported (e.g., in-memory database)
  end
  Sequel.extension :migration
end
