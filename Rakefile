ENV["SKIP_APP_CONFIGURE"] = "1"
require 'sinatra/activerecord/rake'
require './app'

# Use SQL schema format to support SQLite FTS5 virtual tables
ActiveRecord.schema_format = :sql

PROJ_ROOT = File.expand_path(__dir__)

Dir["#{PROJ_ROOT}/lib/tasks/**/*.rake"].each do |path|
  load path
end

namespace :pj do
  desc "Load metadata from files into database"
  task :load_metadata do
    Rake::Task["metadata:load"].invoke
  end
end
