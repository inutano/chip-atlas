# frozen_string_literal: true

require_relative '../test_helper'

class ExperimentSearchTest < Minitest::Test
  include TestHelper

  def setup
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX018625', 'SRA123', 'GSM456', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'H3K4me3 ChIP-seq in K-562 cells', 'leukemia cell line');
    SQL
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX018626', 'SRA124', 'GSM457', 'hg38', 'TFs and others', 'CTCF', 'Blood', 'K-562', 'CTCF ChIP-seq in K-562', 'cell line');
    SQL
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX100002', 'SRA200', 'GSM500', 'mm10', 'ATAC-Seq', '-', 'Liver', 'Hepatocyte', 'ATAC-seq mouse liver', 'primary cell');
    SQL
  end

  def test_search_by_keyword
    result = ChipAtlas::ExperimentSearch.search('K-562')
    assert_equal 2, result[:total]
    assert result[:experiments].all? { |e| e[:expid] }
  end

  def test_search_with_genome_filter
    result = ChipAtlas::ExperimentSearch.search('ATAC', genome: 'mm10')
    assert_equal 1, result[:total]
    assert_equal 'SRX100002', result[:experiments].first[:expid]
  end

  def test_search_with_limit
    result = ChipAtlas::ExperimentSearch.search('K-562', limit: 1)
    assert_equal 2, result[:total]
    assert_equal 1, result[:returned]
  end

  def test_search_empty_query
    result = ChipAtlas::ExperimentSearch.search('')
    assert_equal 0, result[:total]
  end

  def test_search_nil_query
    result = ChipAtlas::ExperimentSearch.search(nil)
    assert_equal 0, result[:total]
  end

  def test_search_with_offset
    result = ChipAtlas::ExperimentSearch.search('K-562', limit: 1, offset: 1)
    assert_equal 2, result[:total]
    assert_equal 1, result[:returned]
  end

  def test_sanitizes_special_characters
    result = ChipAtlas::ExperimentSearch.search('"CTCF" AND (test)')
    assert result.key?(:total)
  end

  def test_sra_cache_set_and_get
    metadata = { exp_id: 'SRX018625', platform: 'ILLUMINA' }
    ChipAtlas::SraCache.set('SRX018625', metadata)
    cached = ChipAtlas::SraCache.get('SRX018625')
    assert_equal 'SRX018625', cached[:exp_id]
    assert_equal 'ILLUMINA', cached[:platform]
  end

  def test_sra_cache_returns_nil_for_missing
    assert_nil ChipAtlas::SraCache.get('NONEXISTENT')
  end

  def test_sra_cache_update_existing
    ChipAtlas::SraCache.set('SRX018625', { v: 1 })
    ChipAtlas::SraCache.set('SRX018625', { v: 2 })
    cached = ChipAtlas::SraCache.get('SRX018625')
    assert_equal 2, cached[:v]
  end
end
