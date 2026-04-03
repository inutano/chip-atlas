ENV['SKIP_APP_CONFIGURE'] = '1'

require 'sequel'
ENV['DATABASE_URL'] ||= "sqlite://database.sqlite"

unless defined?(DB)
  DB = Sequel.connect(ENV['DATABASE_URL'])
end

$LOAD_PATH << __dir__
$LOAD_PATH << File.join(__dir__, 'lib')

Sequel.extension :migration
require 'lib/chip_atlas'
require 'rake'
require 'json'

PROJ_ROOT = File.expand_path(__dir__)

namespace :db do
  desc "Run database migrations"
  task :migrate do
    Sequel::Migrator.run(DB, File.join(PROJ_ROOT, 'db', 'migrations'))
    puts "Migrations complete"
  end

  desc "Reset database (drop all tables and re-migrate)"
  task :reset do
    DB.tables.each { |t| DB.drop_table(t) }
    DB.run("DROP TABLE IF EXISTS experiments_fts")
    Rake::Task['db:migrate'].invoke
    puts "Database reset complete"
  end
end

Dir["#{PROJ_ROOT}/lib/tasks/**/*.rake"].each { |path| load path }
