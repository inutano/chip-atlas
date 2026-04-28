# frozen_string_literal: true

require_relative '../test_helper'

class AnalysisTest < Minitest::Test
  include TestHelper

  def setup
    seed_analyses
  end

  def test_colo_result_by_genome
    result = ChipAtlas::Analysis.colo_result_by_genome('hg38')

    assert result.key?('hg38')
    track_index = result['hg38'][:track]
    cell_type_index = result['hg38'][:cell_type]

    # Track -> cell_types mapping
    assert_equal %w[K-562 HeLa-S3 GM12878], track_index['CTCF']
    assert_equal %w[K-562 Neuron], track_index['H3K4me3']

    # Cell_type -> tracks mapping
    assert_includes cell_type_index['K-562'], 'CTCF'
    assert_includes cell_type_index['K-562'], 'H3K4me3'
    assert_includes cell_type_index['HeLa-S3'], 'CTCF'
    assert_includes cell_type_index['GM12878'], 'CTCF'
    assert_includes cell_type_index['Neuron'], 'H3K4me3'
  end

  def test_colo_result_by_genome_empty
    result = ChipAtlas::Analysis.colo_result_by_genome('dm6')

    assert result.key?('dm6')
    assert_empty result['dm6'][:track]
    assert_empty result['dm6'][:cell_type]
  end

  def test_target_genes_result
    result = ChipAtlas::Analysis.target_genes_result

    assert result.key?('hg38')
    assert_includes result['hg38'], 'CTCF'
    refute_includes result['hg38'], 'H3K4me3'
  end

  def test_target_genes_distances
    distances = ChipAtlas::Analysis.target_genes_distances

    assert_equal 3, distances.size
    distances.each do |item|
      assert item.key?(:id), "Expected key :id in distance option"
      assert item.key?(:label), "Expected key :label in distance option"
    end
    assert_equal '1', distances.first[:id]
    assert_equal '10 kb', distances.last[:label]
  end
end
