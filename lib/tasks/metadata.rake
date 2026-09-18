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
  adv_json_fpath          = File.join(metadata_dir, 'ExperimentList_adv.json')
  bedfile_table_fpath     = File.join(metadata_dir, 'fileList.tab')
  analysis_table_fpath    = File.join(metadata_dir, 'analysisList.tab')
  bedsize_table_fpath     = File.join(metadata_dir, 'lineNum.tsv')
  metadata_base = 'https://chip-atlas.dbcls.jp/data/metadata'
  util_base     = 'https://chip-atlas.dbcls.jp/data/util'

  file experiment_table_fpath => metadata_dir do |t|
    puts 'Downloading experiments metadata...'
    start = Time.now
    download_file("#{metadata_base}/experimentList.tab", t.name)
    puts "   Downloaded experimentList.tab (#{sprintf('%.2f', Time.now - start)}s)"
  end

  # ChipAtlas::Experiment.load_from_files reconciles this against
  # experimentList.tab - it is the only source of sra_id/geo_id and is
  # needed alongside the tab file, not instead of it (see load_experiment
  # below and lib/models/experiment.rb for why one file can't do the job).
  file adv_json_fpath => metadata_dir do |t|
    puts 'Downloading experiments (advanced) metadata...'
    start = Time.now
    download_file("#{metadata_base}/ExperimentList_adv.json", t.name)
    puts "   Downloaded ExperimentList_adv.json (#{sprintf('%.2f', Time.now - start)}s)"
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

  task :load => [:load_experiment, :load_bedfile, :load_analysis, :load_bedsize] do
    puts 'All metadata loading completed successfully!'
  end

  # Loads BOTH the experiments table and the experiments_fts search index
  # from one reconciled row set built out of experimentList.tab (the only
  # source with real per-genome QC stats) and ExperimentList_adv.json (the
  # only source with real sra_id/geo_id) - see
  # ChipAtlas::Experiment.load_from_files for the full reconciliation rule
  # and why a single file can't feed both stores. There is no separate
  # load_fts task any more - the old one loaded ExperimentList_adv.json on
  # its own, trusting its genome claims unconditionally, which is exactly
  # what let the two stores drift apart (219 ids searchable but 404ing on
  # /view, 541 Annotation tracks rows in the table but silently
  # unsearchable). The consistency assertion below fails the build loudly
  # if that ever happens again.
  task :load_experiment => [experiment_table_fpath, adv_json_fpath] do
    puts '[1/4] Loading experiments and search index...'
    start = Time.now
    DB[:experiments].delete
    DB[:experiments_fts].delete
    stats = ChipAtlas::Experiment.load_from_files(experiment_table_fpath, adv_json_fpath)
    ChipAtlas::ExperimentSearch.assert_no_orphaned_fts_rows!
    puts "   #{stats[:experiments]} experiments loaded, #{stats[:indexed]} indexed for search " \
         "(#{sprintf('%.2f', Time.now - start)}s)"
    puts "   #{stats[:tab_only]} tab-only rows excluded from the index (no matching/confirming " \
         'JSON row - includes every Annotation tracks row)'
    puts "   #{stats[:json_only]} JSON-only (experiment_id, genome) pairs dropped entirely " \
         '(JSON claimed a genome the tab file never confirms for that id)'
  end

  task :load_bedfile => bedfile_table_fpath do
    puts '[2/4] Loading bedfiles data...'
    start = Time.now
    DB[:bedfiles].delete
    count = ChipAtlas::Bedfile.load_from_file(bedfile_table_fpath)
    puts "   #{count} bedfiles loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_analysis => analysis_table_fpath do
    puts '[3/4] Loading analysis data...'
    start = Time.now
    DB[:analyses].delete
    count = ChipAtlas::Analysis.load_from_file(analysis_table_fpath)
    puts "   #{count} analyses loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end

  task :load_bedsize => bedsize_table_fpath do
    puts '[4/4] Loading bedsize data...'
    start = Time.now
    DB[:bedsizes].delete
    count = ChipAtlas::Bedsize.load_from_file(bedsize_table_fpath)
    puts "   #{count} bedsizes loaded (#{sprintf('%.2f', Time.now - start)}s)"
  end
end
