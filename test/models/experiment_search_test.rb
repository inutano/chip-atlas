# frozen_string_literal: true

require_relative '../test_helper'

class ExperimentSearchTest < Minitest::Test
  include TestHelper

  def setup
    DB.run <<-SQL
      INSERT INTO experiments_fts (experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes)
      VALUES ('SRX018625', 'SRA123', 'GSM456', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'H3K4me3 ChIP-seq in K-562 cells', 'leukemia cell line');
    SQL
    DB.run <<-SQL
      INSERT INTO experiments_fts (experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes)
      VALUES ('SRX018626', 'SRA124', 'GSM457', 'hg38', 'TFs and others', 'CTCF', 'Blood', 'K-562', 'CTCF ChIP-seq in K-562', 'cell line');
    SQL
    DB.run <<-SQL
      INSERT INTO experiments_fts (experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes)
      VALUES ('SRX100002', 'SRA200', 'GSM500', 'mm10', 'ATAC-Seq', '-', 'Liver', 'Hepatocyte', 'ATAC-seq mouse liver', 'primary cell');
    SQL
  end

  def test_search_by_keyword
    result = ChipAtlas::ExperimentSearch.search('K-562')
    assert_equal 2, result[:total]
    assert result[:experiments].all? { |e| e[:experiment_id] }
  end

  def test_search_with_genome_filter
    result = ChipAtlas::ExperimentSearch.search('ATAC', genome: 'mm10')
    assert_equal 1, result[:total]
    assert_equal 'SRX100002', result[:experiments].first[:experiment_id]
  end

  def test_search_with_limit
    result = ChipAtlas::ExperimentSearch.search('K-562', limit: 1)
    assert_equal 2, result[:total]
    assert_equal 1, result[:returned]
  end

  def test_search_empty_query
    result = ChipAtlas::ExperimentSearch.search('')
    assert_equal 3, result[:total]
  end

  def test_search_nil_query
    result = ChipAtlas::ExperimentSearch.search(nil)
    assert_equal 3, result[:total]
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

  # --- match_expression: turning a user query into an FTS5 MATCH string ---

  def test_match_expression_prefixes_a_bare_term
    assert_equal '"K56"*', ChipAtlas::ExperimentSearch.match_expression('K56')
  end

  def test_match_expression_prefixes_each_space_separated_term
    assert_equal '"K562"* "chip"*', ChipAtlas::ExperimentSearch.match_expression('K562 chip')
  end

  def test_match_expression_keeps_a_term_below_min_prefix_length_exact
    assert_equal '"a"', ChipAtlas::ExperimentSearch.match_expression('a')
  end

  def test_match_expression_keeps_a_quoted_phrase_whole
    assert_equal '"chip antibody"* "K56"*',
                 ChipAtlas::ExperimentSearch.match_expression('"chip antibody" K56')
  end

  def test_match_expression_absorbs_the_users_own_star
    assert_equal '"K56"*', ChipAtlas::ExperimentSearch.match_expression('K56*')
  end

  def test_match_expression_neutralises_operator_keywords
    assert_equal '"a" "AND"* "b"', ChipAtlas::ExperimentSearch.match_expression('a AND b')
  end

  def test_match_expression_is_empty_for_metacharacter_only_input
    assert_equal '', ChipAtlas::ExperimentSearch.match_expression('***')
    assert_equal '', ChipAtlas::ExperimentSearch.match_expression('""')
    assert_equal '', ChipAtlas::ExperimentSearch.match_expression('   ')
  end

  # A shorter prefix must never lose hits the longer one finds. The shared
  # setup only ever writes the hyphenated "K-562" (which FTS5 tokenizes as
  # the adjacent pair "k" "562", not a single "k562" token - see
  # test_search_by_keyword), so an unhyphenated literal is added here,
  # local to this test, to give 'K562' a real single-token hit to compare
  # against without disturbing the row counts other tests depend on.
  def test_search_with_a_shorter_prefix_finds_a_superset
    DB.run <<-SQL
      INSERT INTO experiments_fts (experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes)
      VALUES ('SRX018627', 'SRA125', 'GSM458', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K562', 'H3K4me3 ChIP-seq in K562 cells', 'leukemia cell line');
    SQL

    narrow_ids = ChipAtlas::ExperimentSearch.search('K562')[:experiments].map { |e| e[:experiment_id] }
    wide_ids   = ChipAtlas::ExperimentSearch.search('K56')[:experiments].map { |e| e[:experiment_id] }

    refute_empty narrow_ids, 'fixture setup should give K562 at least one literal hit'
    assert_empty narrow_ids - wide_ids, 'every K562 hit must also be a K56 hit'
  end

  def test_blank_query_lists_all_experiments
    result = ChipAtlas::ExperimentSearch.search('', limit: 2, offset: 0)
    assert_operator result[:total], :>, 0, 'blank query must list everything'
    assert_equal 2, result[:experiments].size
  end

  def test_blank_query_respects_genome_filter
    result = ChipAtlas::ExperimentSearch.search('', genome: 'hg38', limit: 10)
    assert result[:experiments].all? { |e| e[:genome] == 'hg38' }
  end

  def test_blank_query_total_is_memoized_across_calls
    # list_all's total row count is cached (see reset_total_count_cache!)
    # instead of recomputed via COUNT(*) OVER() on every call - it must
    # still reflect the current data and stay correct across repeated
    # calls within the same process.
    first = ChipAtlas::ExperimentSearch.search('', limit: 1)
    second = ChipAtlas::ExperimentSearch.search('', limit: 1, offset: 2)
    assert_equal first[:total], second[:total]
    assert_equal 3, first[:total]
  end

  def test_total_count_cache_is_reset_after_data_reload
    ChipAtlas::ExperimentSearch.search('', limit: 1) # warm the cache at 3 rows
    DB.run <<-SQL
      INSERT INTO experiments_fts (experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes)
      VALUES ('SRX999999', 'SRA999', 'GSM999', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'extra row', 'extra');
    SQL
    ChipAtlas::ExperimentSearch.reset_total_count_cache!
    result = ChipAtlas::ExperimentSearch.search('', limit: 1)
    assert_equal 4, result[:total]
  end

  # --- Annotation tracks: explicit, tested exclusion from the index ---

  def test_indexable_excludes_annotation_tracks
    refute ChipAtlas::ExperimentSearch.indexable?('Annotation tracks')
    assert ChipAtlas::ExperimentSearch.indexable?('Histone')
    assert ChipAtlas::ExperimentSearch.indexable?('ATAC-Seq')
  end

  # --- Consistency gate: every experiments_fts row needs an experiments row ---

  def test_orphaned_count_is_zero_once_every_fts_row_has_a_match
    # setup already seeded 3 experiments_fts rows (SRX018625, SRX018626,
    # SRX100002) with nothing in `experiments` yet - give each a matching
    # experiments row so none is orphaned.
    DB[:experiments].multi_insert([
      { experiment_id: 'SRX018625', genome: 'hg38', track_class: 'Histone', created_at: Time.now },
      { experiment_id: 'SRX018626', genome: 'hg38', track_class: 'TFs and others', created_at: Time.now },
      { experiment_id: 'SRX100002', genome: 'mm10', track_class: 'ATAC-Seq', created_at: Time.now },
    ])

    assert_equal 0, ChipAtlas::ExperimentSearch.orphaned_count
    ChipAtlas::ExperimentSearch.assert_no_orphaned_fts_rows! # must not raise
  end

  # This is the "the gate actually fails" test: nothing has ever seen
  # assert_no_orphaned_fts_rows! raise until this test proves it does, on
  # data shaped exactly like the production bug (a search hit with no
  # matching experiments row, so /view 404s on click).
  def test_assert_no_orphaned_fts_rows_raises_on_an_inconsistent_pair
    # setup's 3 experiments_fts rows have no matching experiments rows
    # here (the experiments table is untouched/empty in this test).
    assert_equal 3, ChipAtlas::ExperimentSearch.orphaned_count

    error = assert_raises(RuntimeError) do
      ChipAtlas::ExperimentSearch.assert_no_orphaned_fts_rows!
    end
    assert_match(/orphaned/, error.message)
  end

  def test_sra_cache_set_and_get
    metadata = { experiment_id: 'SRX018625', platform: 'ILLUMINA' }
    ChipAtlas::SraCache.set('SRX018625', metadata)
    cached = ChipAtlas::SraCache.get('SRX018625')
    assert_equal 'SRX018625', cached[:experiment_id]
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
