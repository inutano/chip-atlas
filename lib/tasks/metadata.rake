# Rakefile to manage local files

namespace :metadata do
  task :load do
    # path to files
    experiment_list = ENV['experiment']
    bedfile_list    = ENV['bedfile']

    open(experiment_list, "r:UTF-8").readlines.each do |line_n|
      line = line_n.chomp.split("\t")

      expid            = line[0]
      genome           = line[1]
      ag_class         = line[2]
      ag_subclass      = line[3]
      cl_class         = line[4]
      cl_subclass      = line[5]
      cl_subclass_info = line[6]
      read_info        = line[7]
      title            = line[8]
      additional_attributes = line[9..line.size].join("\t")

      exp = Experiment.new
      exp.expid      = expid
      exp.genome     = genome
      exp.agClass    = ag_class
      exp.agSubClass = ag_subclass
      exp.clClass    = cl_class
      exp.clSubClass = cl_subclass
      exp.clSubClassInfo = cl_subclass_info
      exp.readInfo   = read_info
      exp.title      = title
      exp.additional_attributes = additional_attributes
      exp.save
    end

    open(bedfile_list, "r:UTF-8").readlines.each do |line_n|
      line = line_n.chomp.split("\t")

      filename    = line[0]
      genome      = line[1]
      ag_class    = line[2]
      ag_subclass = line[3]
      cl_class    = line[4]
      cl_subclass = line[5]
      qvalue      = line[6]
      experiments = line[7]

      bed = Bedfile.new
      bed.filename    = filename
      bed.genome      = genome
      bed.agClass     = ag_class
      bed.agSubClass  = ag_subclass
      bed.clClass     = cl_class
      bed.clSubClass  = cl_subclass
      bed.qval        = qvalue
      bed.experiments = experiments
      bed.save
    end
  end

  #
  # Download metadata tables from NBDC
  #

  table_dir = File.join(PROJ_ROOT, "table")
  directory table_dir

  experiment_list_fpath = File.join(table_dir, "experimentList.tab")
  file_list_fpath       = File.join(table_dir, "fileList.tab")
  analysis_list_fpath   = File.join(table_dir, "analysisList.tab")
  line_num_fpath        = File.join(table_dir, "lineNum.tsv")

  task :fetch => [
    experiment_list_fpath,
    file_list_fpath,
    analysis_list_fpath,
    line_num_fpath
  ]

  file experiment_list_fpath => table_dir do |t|
    PJ::Metadata.fetch(t.name)
  end

  file file_list_fpath => table_dir do |t|
    PJ::Metadata.fetch(t.name)
  end

  file analysis_list_fpath => table_dir do |t|
    PJ::Metadata.fetch(t.name)
  end

  file line_num_fpath => table_dir do |t|
    PJ::Metadata.fetch(t.name)
  end
end
