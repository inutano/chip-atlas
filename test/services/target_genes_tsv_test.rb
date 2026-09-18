# frozen_string_literal: true

require_relative '../test_helper'

class TargetGenesTsvTest < Minitest::Test
  FIXTURE_PATH = File.join(__dir__, '..', 'fixtures', 'target_genes_sample.tsv')
  URL = 'https://chip-atlas.dbcls.jp/data/mm10/target/Stat3.1.tsv'

  def setup
    @fixture = File.read(FIXTURE_PATH)
  end

  def teardown
    ChipAtlas::TargetGenesTsv.fetcher = nil
    super
  end

  def stub_fetcher(body_or_map)
    ChipAtlas::TargetGenesTsv.fetcher = lambda do |url|
      body_or_map.is_a?(Hash) ? body_or_map[url] : body_or_map
    end
  end

  def fetch(**overrides)
    ChipAtlas::TargetGenesTsv.result(
      genome: 'mm10', track: 'Stat3', distance: '1', tsv_url: URL, **overrides
    )
  end

  # --- shape / headers ---

  def test_result_returns_columns_separately_from_rows
    stub_fetcher(@fixture)
    result = fetch
    assert_equal %w[Target_genes Stat3|Average SRX361677|Astrocytes SRX400001|Neuron STRING], result[:columns]
    assert_equal 5, result[:total]
    assert_kind_of Array, result[:rows].first
  end

  # --- default sort: the |Average column, descending ---

  def test_default_sort_is_average_column_descending
    stub_fetcher(@fixture)
    result = fetch
    symbols = result[:rows].map(&:first)
    assert_equal %w[Myc Stat3 Bcl2 Socs3 Il6], symbols
  end

  def test_order_asc_reverses_the_default_sort
    stub_fetcher(@fixture)
    result = fetch(order: 'asc')
    symbols = result[:rows].map(&:first)
    assert_equal %w[Il6 Socs3 Bcl2 Stat3 Myc], symbols
  end

  # --- sort by a chosen column, both orders ---

  def test_sort_by_a_named_experiment_column_descending
    stub_fetcher(@fixture)
    result = fetch(sort: 'SRX361677|Astrocytes')
    symbols = result[:rows].map(&:first)
    # Astrocytes column: Stat3=665 Socs3=300 Il6=450 Bcl2=900 Myc=1000
    assert_equal %w[Myc Bcl2 Stat3 Il6 Socs3], symbols
  end

  def test_sort_by_a_named_experiment_column_ascending
    stub_fetcher(@fixture)
    result = fetch(sort: 'SRX361677|Astrocytes', order: 'asc')
    symbols = result[:rows].map(&:first)
    assert_equal %w[Socs3 Il6 Stat3 Bcl2 Myc], symbols
  end

  def test_unknown_sort_column_raises
    stub_fetcher(@fixture)
    assert_raises(ChipAtlas::TargetGenesTsv::UnknownSortColumn) { fetch(sort: 'NoSuchColumn') }
  end

  # --- offset/limit slicing, including the last partial page ---

  def test_offset_and_limit_slice_pages
    stub_fetcher(@fixture)
    page1 = fetch(limit: 2, offset: 0)
    assert_equal %w[Myc Stat3], page1[:rows].map(&:first)
    assert_equal 0, page1[:offset]
    assert_equal 2, page1[:limit]
    assert_equal 5, page1[:total]

    page2 = fetch(limit: 2, offset: 2)
    assert_equal %w[Bcl2 Socs3], page2[:rows].map(&:first)

    last_page = fetch(limit: 2, offset: 4)
    assert_equal %w[Il6], last_page[:rows].map(&:first), 'the last, partial page must return only the remaining row'
  end

  def test_offset_past_the_end_returns_an_empty_page_not_an_error
    stub_fetcher(@fixture)
    result = fetch(limit: 10, offset: 100)
    assert_equal [], result[:rows]
    assert_equal 5, result[:total]
  end

  # --- limit cap ---

  def test_limit_is_capped_server_side
    stub_fetcher(@fixture)
    result = fetch(limit: 999_999)
    assert_equal ChipAtlas::TargetGenesTsv::MAX_LIMIT, result[:limit]
  end

  def test_limit_defaults_when_absent
    stub_fetcher(@fixture)
    result = fetch
    assert_equal ChipAtlas::TargetGenesTsv::DEFAULT_LIMIT, result[:limit]
  end

  def test_zero_or_negative_limit_falls_back_to_default
    stub_fetcher(@fixture)
    assert_equal ChipAtlas::TargetGenesTsv::DEFAULT_LIMIT, fetch(limit: 0)[:limit]
    assert_equal ChipAtlas::TargetGenesTsv::DEFAULT_LIMIT, fetch(limit: -5)[:limit]
  end

  # --- missing vs malformed ---

  def test_missing_combination_returns_nil
    stub_fetcher(nil)
    assert_nil fetch
  end

  def test_malformed_body_raises_parse_error_distinct_from_missing
    stub_fetcher("just one column\n")
    assert_raises(ChipAtlas::TargetGenesTsv::ParseError) { fetch }
  end

  def test_empty_body_raises_parse_error
    stub_fetcher('')
    assert_raises(ChipAtlas::TargetGenesTsv::ParseError) { fetch }
  end

  # --- caching ---

  def test_result_is_cached_and_does_not_refetch_within_ttl
    calls = []
    ChipAtlas::TargetGenesTsv.fetcher = lambda { |url| calls << url; @fixture }

    3.times { fetch }
    assert_equal 1, calls.size, 'a fresh cache entry must not be refetched on every request'
  end

  def test_result_refetches_after_ttl_expires
    calls = []
    ChipAtlas::TargetGenesTsv.fetcher = lambda { |url| calls << url; @fixture }

    fetch
    assert_equal 1, calls.size

    cache = ChipAtlas::TargetGenesTsv.instance_variable_get(:@cache)
    entry = cache.fetch('mm10/Stat3/1')
    entry[:cached_at] = Time.now - (ChipAtlas::TargetGenesTsv::TTL + 1)

    fetch
    assert_equal 2, calls.size, 'an expired entry must be refetched, not served stale forever'
  end

  def test_different_track_distance_pairs_get_independent_cache_entries
    calls = []
    ChipAtlas::TargetGenesTsv.fetcher = lambda { |url| calls << url; @fixture }

    ChipAtlas::TargetGenesTsv.result(genome: 'mm10', track: 'Stat3', distance: '1', tsv_url: URL)
    ChipAtlas::TargetGenesTsv.result(genome: 'mm10', track: 'Stat3', distance: '5', tsv_url: URL)
    assert_equal 2, calls.size
  end

  # --- the cache is bounded by an estimated byte budget, not just entry count ---

  def test_cache_is_bounded_by_byte_budget_with_fifo_eviction
    stub_fetcher(@fixture)

    with_max_cache_bytes(1) do # smaller than even one row; every store is a no-op
      fetch
      cache = ChipAtlas::TargetGenesTsv.instance_variable_get(:@cache)
      assert_empty cache, 'an entry larger than the byte budget must not be cached at all'
    end
  end

  def test_cache_evicts_oldest_entry_once_the_byte_budget_is_exceeded
    calls = []
    ChipAtlas::TargetGenesTsv.fetcher = lambda { |url| calls << url; @fixture }

    # One parsed fixture entry is 5 rows x 5 cols: 5 * (40 + 5*8) = 400 bytes
    # (see ChipAtlas::TargetGenesTsv's byte estimate). Budget room for
    # exactly one entry at a time forces FIFO eviction on the second store.
    with_max_cache_bytes(450) do
      ChipAtlas::TargetGenesTsv.result(genome: 'mm10', track: 'Stat3', distance: '1', tsv_url: URL)
      ChipAtlas::TargetGenesTsv.result(genome: 'mm10', track: 'Stat3', distance: '5', tsv_url: URL)

      cache = ChipAtlas::TargetGenesTsv.instance_variable_get(:@cache)
      assert_equal 1, cache.size, 'the byte budget must bound the cache even when entry count is small'
      refute cache.key?('mm10/Stat3/1'), 'the oldest entry should have been evicted first (FIFO)'
      assert cache.key?('mm10/Stat3/5')

      # Re-requesting the evicted key must refetch, proving it's really gone.
      ChipAtlas::TargetGenesTsv.result(genome: 'mm10', track: 'Stat3', distance: '1', tsv_url: URL)
      assert_equal 3, calls.size
    end
  end

  private

  def with_max_cache_bytes(value)
    original = ChipAtlas::TargetGenesTsv::MAX_CACHE_BYTES
    silence_warnings do
      ChipAtlas::TargetGenesTsv.send(:remove_const, :MAX_CACHE_BYTES)
      ChipAtlas::TargetGenesTsv.const_set(:MAX_CACHE_BYTES, value)
    end
    yield
  ensure
    silence_warnings do
      ChipAtlas::TargetGenesTsv.send(:remove_const, :MAX_CACHE_BYTES)
      ChipAtlas::TargetGenesTsv.const_set(:MAX_CACHE_BYTES, original)
    end
    ChipAtlas::TargetGenesTsv.reset!
  end

  def silence_warnings
    original_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = original_verbose
  end
end
