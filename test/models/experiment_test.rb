# frozen_string_literal: true

require_relative '../test_helper'

class ExperimentTest < Minitest::Test
  include TestHelper

  def setup
    seed_experiments
  end

  def test_list_of_genome
    genomes = ChipAtlas::Experiment.list_of_genome
    assert_includes genomes.keys, 'hg38'
    assert_includes genomes.keys, 'mm10'
    assert_includes genomes.keys, 'TAIR12'
    assert_equal 'H. sapiens (hg38)', genomes['hg38']
  end

  # Proves the registry is config-driven: ids, labels, and their order come
  # from whatever YAML file genomes_config_path points at, not from a Ruby
  # constant. Points the registry at a fixture with a different id set and
  # order than config/genomes.yml and checks the result changes to match.
  def test_genome_registry_is_config_driven
    ChipAtlas::Experiment.genomes_config_path =
      File.join(__dir__, '..', 'fixtures', 'genomes_sample.yml')

    assert_equal %w[zz99 aa11 mm00], ChipAtlas::Experiment.genomes.keys
    assert_equal 'Z. zzyzxus (zz99)', ChipAtlas::Experiment.genomes['zz99']
    assert_equal({ 'zz99' => 0, 'aa11' => 1, 'mm00' => 2 }, ChipAtlas::Experiment.genome_order)
    refute_includes ChipAtlas::Experiment.genomes.keys, 'hg38'
  ensure
    ChipAtlas::Experiment.reset_genomes_config_path!
  end

  def test_list_of_experiment_types
    types = ChipAtlas::Experiment.list_of_experiment_types
    assert types.any? { |t| t[:id] == 'Histone' }
    assert types.any? { |t| t[:id] == 'CUT&Tag' }
    assert types.any? { |t| t[:id] == 'CUT&RUN' }
  end

  def test_experiment_types_with_counts
    result = ChipAtlas::Experiment.experiment_types('hg38', 'All cell types')
    histone = result.find { |r| r[:id] == 'Histone' }
    assert_equal 2, histone[:count]
  end

  def test_experiment_types_filtered_by_cell_class
    result = ChipAtlas::Experiment.experiment_types('hg38', 'Blood')
    histone = result.find { |r| r[:id] == 'Histone' }
    assert_equal 1, histone[:count]
  end

  def test_sample_types
    result = ChipAtlas::Experiment.sample_types('hg38', 'Histone')
    assert_equal 'All cell types', result.first[:id]
    assert_equal 2, result.first[:count]
    blood = result.find { |r| r[:id] == 'Blood' }
    assert_equal 1, blood[:count]
  end

  def test_chip_antigen
    result = ChipAtlas::Experiment.chip_antigen('hg38', 'Histone', 'All cell types')
    assert_equal '-', result.first[:id]
    h3k4 = result.find { |r| r[:id] == 'H3K4me3' }
    assert_equal 1, h3k4[:count]
  end

  def test_cell_type
    result = ChipAtlas::Experiment.cell_type('hg38', 'Histone', 'Blood')
    assert_equal '-', result.first[:id]
    k562 = result.find { |r| r[:id] == 'K-562' }
    assert_equal 1, k562[:count]
  end

  def test_cell_type_returns_only_all_when_no_class
    result = ChipAtlas::Experiment.cell_type('hg38', 'Histone', 'All cell types')
    assert_equal 1, result.size
    assert_equal '-', result.first[:id]
  end

  def test_record_by_experiment_id
    records = ChipAtlas::Experiment.record_by_experiment_id('SRX018625')
    assert_equal 1, records.size
    assert_equal 'SRX018625', records.first[:experiment_id]
    assert_equal 'Histone', records.first[:track_class]
  end

  def test_id_valid
    assert ChipAtlas::Experiment.id_valid?('SRX018625')
    refute ChipAtlas::Experiment.id_valid?('NONEXISTENT')
  end

  def test_number_of_experiments
    count = ChipAtlas::Experiment.number_of_experiments
    assert_equal 4, count
  end

  def test_total_number_of_reads
    total = ChipAtlas::Experiment.total_number_of_reads(['SRX018625', 'SRX018626'])
    assert_equal 35000000, total
  end

  def test_index_all_genome
    index = ChipAtlas::Experiment.index_all_genome
    assert index.key?('hg38')
    assert index['hg38'].key?(:track)
    assert index['hg38'].key?(:cell_type)
    assert index['hg38'][:track].key?('Histone')
  end

  # --- load_from_file: one source feeding both experiments and experiments_fts ---
  #
  # Fixture (test/fixtures/experimentList_sample.tab) has 4 rows:
  #   SRXTEST001  hg38  Histone            - title starts "GSM100001: ..."
  #   SRXTEST002  hg38  Annotation tracks   - excluded from the search index
  #   SRXTEST003  mm10  ATAC-Seq            - title has no GSM prefix
  #   SRXTEST004  xx99  Histone             - xx99 is not in config/genomes.yml

  def test_load_from_file_loads_experiments_and_search_index_together
    DB[:experiments].delete
    DB[:experiments_fts].delete

    fixture = File.join(__dir__, '..', 'fixtures', 'experimentList_sample.tab')
    count = ChipAtlas::Experiment.load_from_file(fixture)

    # The unsupported genome (xx99) is dropped by the same filter for both
    # stores - only 3 of the 4 fixture rows are loadable at all.
    assert_equal 3, count
    assert_equal 3, DB[:experiments].count
    refute ChipAtlas::Experiment.id_valid?('SRXTEST004')

    # Annotation tracks load into experiments (so /view still works for
    # them) but are excluded from the search index on purpose.
    assert ChipAtlas::Experiment.id_valid?('SRXTEST002')
    assert_equal 2, DB[:experiments_fts].count
    refute DB[:experiments_fts].where(experiment_id: 'SRXTEST002').first

    # geo_id is recovered from the "GSM######: ..." title convention so
    # /view?id=GSM... redirects keep working even without a dedicated
    # geo_id column in experimentList.tab.
    with_gsm = DB[:experiments_fts].where(experiment_id: 'SRXTEST001').first
    assert_equal 'GSM100001', with_gsm[:geo_id]

    # A title with no GSM prefix gets a blank geo_id, not a crash or a
    # bogus partial match.
    without_gsm = DB[:experiments_fts].where(experiment_id: 'SRXTEST003').first
    assert_equal '', without_gsm[:geo_id]

    # experimentList.tab has no SRA study accession column - sra_id is
    # left blank rather than fabricated.
    assert_equal '', with_gsm[:sra_id]

    # The structural guarantee this task is about: every experiments_fts
    # row has a matching experiments row.
    assert_equal 0, ChipAtlas::ExperimentSearch.orphaned_count
  end

  def test_experiments_and_search_totals_differ_by_annotation_track_count
    DB[:experiments].delete
    DB[:experiments_fts].delete

    fixture = File.join(__dir__, '..', 'fixtures', 'experimentList_sample.tab')
    ChipAtlas::Experiment.load_from_file(fixture)

    annotation_track_count =
      DB[:experiments].where(track_class: 'Annotation tracks').count
    assert_equal 1, annotation_track_count

    total_experiments = ChipAtlas::Experiment.number_of_experiments
    search_total = ChipAtlas::ExperimentSearch.total_count
    assert_equal total_experiments - annotation_track_count, search_total
  end
end
