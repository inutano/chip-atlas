# Rakefile to manage local files

namespace :metadata do
  #
  # Create metadata directory
  #

  datetime = Time.now.strftime("%Y%m%d-%H%M")
  metadata_dir = ENV['metadata_dir'] || File.join(PROJ_ROOT, "metadata", datetime)
  directory metadata_dir

  #
  # Download metadata tables from NBDC
  #

  experiment_table_fpath  = File.join(metadata_dir, "experimentList.tab")
  bedfile_table_fpath     = File.join(metadata_dir, "fileList.tab")
  analysis_table_fpath    = File.join(metadata_dir, "analysisList.tab")
  bedsize_table_fpath     = File.join(metadata_dir, "lineNum.tsv")
  run_members_table_fpath = File.join(metadata_dir, "SRA_Run_Members.tab")

  file experiment_table_fpath => metadata_dir do |t|
    puts "Downloading experiments metadata..."
    start_time = Time.now
    PJ::Metadata.fetch(t.name)
    puts "   Downloaded experimentList.tab (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  file bedfile_table_fpath => metadata_dir do |t|
    puts "Downloading bedfiles metadata..."
    start_time = Time.now
    PJ::Metadata.fetch(t.name)
    puts "   Downloaded fileList.tab (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  file analysis_table_fpath => metadata_dir do |t|
    puts "Downloading analysis metadata..."
    start_time = Time.now
    PJ::Metadata.fetch(t.name)
    puts "   Downloaded analysisList.tab (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  file bedsize_table_fpath => metadata_dir do |t|
    puts "Downloading bedsize metadata..."
    start_time = Time.now
    PJ::Metadata.fetch(t.name)
    puts "   Downloaded lineNum.tsv (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  file run_members_table_fpath => metadata_dir do |t|
    puts "Downloading SRA run members metadata..."
    start_time = Time.now
    PJ::Run.fetch(t.name)
    puts "   Downloaded SRA_Run_Members.tab (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  #
  # Metadata table loading task
  #

  task :load => [
    :load_experiment,
    :load_bedfile,
    :load_analysis,
    :load_bedsize,
    :load_run
  ] do
    puts "All metadata loading completed successfully!"
  end

  task :load_experiment => experiment_table_fpath do |t|
    puts "[1/5] Loading experiments data..."
    start_time = Time.now
    PJ::Experiment.load(experiment_table_fpath)
    puts "   Experiments loaded (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  task :load_bedfile => bedfile_table_fpath do |t|
    puts "[2/5] Loading bedfiles data..."
    start_time = Time.now
    PJ::Bedfile.load(bedfile_table_fpath)
    puts "   Bedfiles loaded (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  task :load_analysis => analysis_table_fpath do |t|
    puts "[3/5] Loading analysis data..."
    start_time = Time.now
    PJ::Analysis.load(analysis_table_fpath)
    puts "   Analysis loaded (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  task :load_bedsize => bedsize_table_fpath do |t|
    puts "[4/5] Loading bedsize data..."
    start_time = Time.now
    PJ::Bedsize.load(bedsize_table_fpath)
    puts "   Bedsize loaded (#{sprintf('%.2f', Time.now - start_time)}s)"
  end

  task :load_run => run_members_table_fpath do |t|
    puts "[5/5] Loading runs data..."
    start_time = Time.now
    PJ::Run.load(run_members_table_fpath)
    puts "   Runs loaded (#{sprintf('%.2f', Time.now - start_time)}s)"
  end
end
