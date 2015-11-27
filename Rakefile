require 'sinatra/activerecord/rake'
require './app'

PROJ_ROOT = File.expand_path(__dir__)

Dir["#{PROJ_ROOT}/lib/tasks/**/*.rake"].each do |path|
  load path
end

namespace :pj do
  desc "Download tables from NBDC"
  task :fetch_metadata do
    Rake::Task["metadata:fetch"].invoke
  end

  desc "Load metadata from files into database"
  task :load_metadata do
    Rake::Task["metadata:load"].invoke
  end
end
