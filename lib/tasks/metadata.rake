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

  experiment_table_fpath = File.join(metadata_dir, "experimentList.tab")
  bedfile_table_fpath    = File.join(metadata_dir, "fileList.tab")
  analysis_table_fpath   = File.join(metadata_dir, "analysisList.tab")
  bedsize_table_fpath    = File.join(metadata_dir, "lineNum.tsv")

  file experiment_table_fpath => metadata_dir do |t|
    PJ::Metadata.fetch(t.name)
  end

  file bedfile_table_fpath => metadata_dir do |t|
    PJ::Metadata.fetch(t.name)
  end

  file analysis_table_fpath => metadata_dir do |t|
    PJ::Metadata.fetch(t.name)
  end

  file bedsize_table_fpath => metadata_dir do |t|
    PJ::Metadata.fetch(t.name)
  end

  #
  # Metadata table loading task
  #

  task :load => [
    :load_experiment,
    :load_bedfile,
    :load_analysis,
    :load_bedsize
  ]

  task :load_experiment => experiment_table_fpath do |t|
    PJ::Experiment.load(experiment_table_fpath)
  end

  task :load_bedfile => bedfile_table_fpath do |t|
    PJ::Bedfile.load(bedfile_table_fpath)
  end

  task :load_analysis => analysis_table_fpath do |t|
    PJ::Analysis.load(analysis_table_fpath)
  end

  task :load_bedsize => bedsize_table_fpath do |t|
    PJ::Bedsize.load(bedsize_table_fpath)
  end
end
