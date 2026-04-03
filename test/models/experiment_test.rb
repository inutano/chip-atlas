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
    assert_includes genomes.keys, 'TAIR10'
    assert_equal 'H. sapiens (hg38)', genomes['hg38']
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

  def test_record_by_exp_id
    records = ChipAtlas::Experiment.record_by_exp_id('SRX018625')
    assert_equal 1, records.size
    assert_equal 'SRX018625', records.first[:expid]
    assert_equal 'Histone', records.first[:agClass]
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
    assert index['hg38'].key?(:antigen)
    assert index['hg38'].key?(:celltype)
    assert index['hg38'][:antigen].key?('Histone')
  end
end
