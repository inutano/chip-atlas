# frozen_string_literal: true

require 'sequel'

unless defined?(DB)
  ENV['DATABASE_URL'] ||= "sqlite://database.sqlite"
  DB = Sequel.connect(ENV['DATABASE_URL'], pool_timeout: 300)
  begin
    DB.run("PRAGMA journal_mode=WAL")
  rescue Sequel::DatabaseError
    # WAL not supported (e.g., in-memory database)
  end
  Sequel.extension :migration
end
