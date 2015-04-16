require 'sinatra/activerecord/rake'
require './app'

PROJ_ROOT = File.expand_path(__dir__)

Dir["#{PROJ_ROOT}/lib/tasks/**/*.rake"].each do |path|
  load path
end

namespace :pj do
  desc "load tables into database; require experiment=/path/to/experimentList.tab bedfile=/path/to/fileList.tab"
  task :load_tables do
    Rake::Task["table:load_tables"].invoke
  end
end
