require 'sequel'

unless defined?(DB)
  ENV['DATABASE_URL'] ||= "sqlite://database.sqlite"
  DB = Sequel.connect(ENV['DATABASE_URL'], pool_timeout: 300)
  DB.run("PRAGMA journal_mode=WAL") rescue nil
  Sequel.extension :migration
end
