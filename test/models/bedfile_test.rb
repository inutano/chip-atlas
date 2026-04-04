# frozen_string_literal: true

require_relative '../test_helper'

class BedfileTest < Minitest::Test
  include TestHelper

  def setup
    seed_bedfiles
  end

  def test_get_filename
    condition = {
      genome: 'hg38', track_class: 'Histone', track_subclass: 'H3K4me3',
      cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05'
    }
    filename = ChipAtlas::Bedfile.get_filename(condition)
    assert_equal 'H3K4me3.Blood.05', filename
  end

  def test_get_filename_raises_on_no_match
    condition = {
      genome: 'hg38', track_class: 'Histone', track_subclass: 'NONEXISTENT',
      cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05'
    }
    assert_raises(ChipAtlas::Bedfile::NotFound) do
      ChipAtlas::Bedfile.get_filename(condition)
    end
  end

  def test_qval_range
    range = ChipAtlas::Bedfile.qval_range
    assert_includes range, '05'
  end

  def test_analysis_colo_result_by_genome
    seed_analyses
    result = ChipAtlas::Analysis.colo_result_by_genome('hg38')
    assert result['hg38'][:track].key?('CTCF')
    assert result['hg38'][:cell_type].key?('K-562')
  end

  def test_analysis_target_genes_result
    seed_analyses
    result = ChipAtlas::Analysis.target_genes_result
    assert_includes result['hg38'], 'CTCF'
    refute_includes result['hg38'], 'H3K4me3'
  end

  def test_bedsize_dump
    seed_bedsizes
    result = ChipAtlas::Bedsize.dump
    assert result.key?('hg38,Histone,Blood,05')
    assert_equal 150000, result['hg38,Histone,Blood,05']
  end
end
