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

    # Verify that experiment data exists first
    experiment_count = PJ::Experiment.count
    if experiment_count == 0
      puts "   ERROR: No experiments found in database!"
      puts "   Please run 'rake metadata:load_experiment' first"
      exit 1
    end
    puts "   Found #{experiment_count} experiments for filtering"

    # Show file size information
    file_size_mb = File.size(run_members_table_fpath) / (1024.0 * 1024.0)
    puts "   Processing file: #{File.basename(run_members_table_fpath)} (#{sprintf('%.1f', file_size_mb)} MB)"

    start_time = Time.now
    initial_count = PJ::Run.count

    PJ::Run.load(run_members_table_fpath)

    end_time = Time.now
    final_count = PJ::Run.count
    new_records = final_count - initial_count

    puts "   Runs loaded: #{new_records} new records added"
    puts "   Total runs in database: #{final_count}"
    puts "   Loading time: #{sprintf('%.2f', end_time - start_time)}s"
  end

  #
  # Benchmark task for performance comparison
  #

  task :benchmark_run => run_members_table_fpath do |t|
    puts "=== Run Loading Performance Benchmark ==="

    # Ensure experiment data exists for filtering
    if PJ::Experiment.count == 0
      puts "Loading experiment data for benchmark..."
      Rake::Task["metadata:load_experiment"].invoke
    end

    # Clear existing run data for clean comparison
    puts "Clearing existing run data..."
    PJ::Run.delete_all

    file_size_mb = File.size(run_members_table_fpath) / (1024.0 * 1024.0)
    puts "File to process: #{File.basename(run_members_table_fpath)} (#{sprintf('%.1f', file_size_mb)} MB)"

    # Benchmark the optimized version
    puts "\n--- Testing Optimized Version (Filtered) ---"
    start_time = Time.now
    PJ::Run.load(run_members_table_fpath)
    optimized_time = Time.now - start_time
    optimized_count = PJ::Run.count

    puts "Optimized results:"
    puts "  - Records loaded: #{optimized_count}"
    puts "  - Time taken: #{sprintf('%.2f', optimized_time)}s"
    puts "  - Records/second: #{sprintf('%.0f', optimized_count / optimized_time)}" if optimized_time > 0

    # Show data reduction stats
    total_live_runs = `awk -F '\t' '$8 == "live"' #{run_members_table_fpath} | wc -l`.to_i
    reduction_pct = (1 - optimized_count.to_f / total_live_runs) * 100

    puts "\nData Reduction Summary:"
    puts "  - Total live runs in file: #{total_live_runs}"
    puts "  - Runs loaded (filtered): #{optimized_count}"
    puts "  - Data reduction: #{sprintf('%.1f', reduction_pct)}%"
    puts "  - Processing efficiency: #{sprintf('%.1f', file_size_mb / optimized_time)} MB/s" if optimized_time > 0

    puts "\n=== Benchmark Complete ==="
  end

  #
  # Validation task to check data integrity
  #

  task :validate_run_data do
    puts "=== Run Data Validation ==="

    run_count = PJ::Run.count
    exp_count = PJ::Experiment.count

    puts "Total runs: #{run_count}"
    puts "Total experiments: #{exp_count}"

    # Check for orphaned runs (runs without corresponding experiments)
    orphaned_runs = PJ::Run.joins("LEFT JOIN experiments ON runs.expid = experiments.expid")
                           .where("experiments.expid IS NULL").count

    if orphaned_runs > 0
      puts "WARNING: Found #{orphaned_runs} runs without corresponding experiments"
    else
      puts "✓ All runs have corresponding experiments"
    end

    # Check experiment coverage
    experiments_with_runs = PJ::Run.distinct.count(:expid)
    coverage_pct = (experiments_with_runs.to_f / exp_count) * 100

    puts "Experiments with runs: #{experiments_with_runs}/#{exp_count} (#{sprintf('%.1f', coverage_pct)}%)"

    puts "=== Validation Complete ==="
  end
end
