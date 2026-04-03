# frozen_string_literal: true

require 'net/http'
require 'uri'

def download_file(url, dest)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  http.open_timeout = 30
  http.read_timeout = 120
  response = http.get(uri.request_uri)
  raise "Download failed: #{response.code} for #{url}" unless response.code == '200'

  File.write(dest, response.body)
end

namespace :metadata do
  datetime = Time.now.strftime('%Y%m%d-%H%M')
  metadata_dir = ENV['metadata_dir'] || File.join(PROJ_ROOT, 'metadata', datetime)
  directory metadata_dir

  experiment_table_fpath  = File.join(metadata_dir, 'experimentList.tab')
  bedfile_table_fpath     = File.join(metadata_dir, 'fileList.tab')
  analysis_table_fpath    = File.join(metadata_dir, 'analysisList.tab')
  bedsize_table_fpath     = File.join(metadata_dir, 'lineNum.tsv')
  run_members_table_fpath = File.join(metadata_dir, 'SRA_Run_Members.tab')

  metadata_base = 'https://chip-atlas.dbcls.jp/data/metadata'
  util_base     = 'https://chip-atlas.dbcls.jp/data/util'

  file experiment_table_fpath => metadata_dir do |t|
    puts 'Downloading experiments metadata...'
    start = Time.now
    download_file("#{metadata_base}/experimentList.tab", t.name)
    puts "   Downloaded experimentList.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file bedfile_table_fpath => metadata_dir do |t|
    puts 'Downloading bedfiles metadata...'
    start = Time.now
    download_file("#{metadata_base}/fileList.tab", t.name)
    puts "   Downloaded fileList.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file analysis_table_fpath => metadata_dir do |t|
    puts 'Downloading analysis metadata...'
    start = Time.now
    download_file("#{metadata_base}/analysisList.tab", t.name)
    puts "   Downloaded analysisList.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file bedsize_table_fpath => metadata_dir do |t|
    puts 'Downloading bedsize metadata...'
    start = Time.now
    download_file("#{util_base}/lineNum.tsv", t.name)
    puts "   Downloaded lineNum.tsv (#{sprintf('%.2f', Time.now - start)}s)"
  end

  file run_members_table_fpath => metadata_dir do |t|
    puts 'Downloading SRA run members metadata...'
    start = Time.now
    base  = 'ftp.ncbi.nlm.nih.gov/sra/reports/Metadata'
    fname = 'SRA_Run_Members.tab'
    `lftp -c "open #{base} && pget -n 8 -O #{File.dirname(t.name)} #{fname}"`
    puts "   Downloaded SRA_Run_Members.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load => [:load_experiment, :load_bedfile, :load_analysis, :load_bedsize, :load_run, :load_fts] do
    puts 'All metadata loading completed successfully!'
  end

  task :load_experiment => experiment_table_fpath do
    puts '[1/6] Loading experiments data...'
    start = Time.now
    DB[:experiments].delete
    count = ChipAtlas::Experiment.load_from_file(experiment_table_fpath)
    puts "   #{count} experiments loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_bedfile => bedfile_table_fpath do
    puts '[2/6] Loading bedfiles data...'
    start = Time.now
    DB[:bedfiles].delete
    count = ChipAtlas::Bedfile.load_from_file(bedfile_table_fpath)
    puts "   #{count} bedfiles loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_analysis => analysis_table_fpath do
    puts '[3/6] Loading analysis data...'
    start = Time.now
    DB[:analyses].delete
    count = ChipAtlas::Analysis.load_from_file(analysis_table_fpath)
    puts "   #{count} analyses loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_bedsize => bedsize_table_fpath do
    puts '[4/6] Loading bedsize data...'
    start = Time.now
    DB[:bedsizes].delete
    count = ChipAtlas::Bedsize.load_from_file(bedsize_table_fpath)
    puts "   #{count} bedsizes loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_run => run_members_table_fpath do
    puts '[5/6] Loading runs data...'
    exp_count = DB[:experiments].count
    if exp_count == 0
      puts '   ERROR: No experiments found. Run metadata:load_experiment first.'
      exit 1
    end
    start = Time.now
    DB[:runs].delete
    count = ChipAtlas::Run.load_from_file(run_members_table_fpath)
    puts "   #{count} runs loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_fts do
    puts '[6/6] Loading FTS5 search index...'
    start = Time.now
    json_path = File.join(PROJ_ROOT, 'public', 'ExperimentList_adv.json')
    if File.exist?(json_path)
      json_data = JSON.parse(File.read(json_path))
      ChipAtlas::ExperimentSearch.load_from_json(json_data)
      puts "   FTS5 index loaded (#{sprintf('%.2f', Time.now - start)}s)"
    else
      puts '   Skipping FTS5: ExperimentList_adv.json not found'
    end
  end
end
