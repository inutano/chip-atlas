# frozen_string_literal: true

require_relative '../test_helper'

class ColoTsvTest < Minitest::Test
  FIXTURE_PATH = File.join(__dir__, '..', 'fixtures', 'colo_sample.tsv')
  URL = 'https://chip-atlas.dbcls.jp/data/hg38/colo/Stat3.CellA.tsv'

  def setup
    @fixture = File.read(FIXTURE_PATH)
  end

  def teardown
    ChipAtlas::ColoTsv.fetcher = nil
    super
  end

  def stub_fetcher(body_or_map)
    ChipAtlas::ColoTsv.fetcher = lambda do |url|
      body_or_map.is_a?(Hash) ? body_or_map[url] : body_or_map
    end
  end

  def fetch
    ChipAtlas::ColoTsv.result(tsv_url: URL)
  end

  # --- shape / headers ---

  def test_result_returns_columns_separately_from_rows
    stub_fetcher(@fixture)
    result = fetch
    assert_equal %w[Experiment Cell_subclass Protein Stat3|Average SRX111111|CellA SRX222222|CellB STRING],
                 result[:columns]
    assert_equal 4, result[:total]
    assert_kind_of Array, result[:rows].first
  end

  def test_leading_identity_columns_stay_strings_the_rest_are_floats
    stub_fetcher(@fixture)
    row = fetch[:rows].find { |r| r[0] == 'SRX100001' }
    assert_equal ['SRX100001', 'CellD', 'Stat3'], row[0..2]
    assert_in_delta 7.5, row[3], 0.0001
    assert_kind_of Float, row[4]
    assert_kind_of Float, row[5]
    assert_kind_of Float, row[6]
  end

  # --- the self-comparison sentinel is just data here (color/label mapping
  # is client-side, see frontend/pages/colo-result.ts) ---

  def test_self_comparison_sentinel_value_is_preserved_verbatim
    stub_fetcher(@fixture)
    row = fetch[:rows].find { |r| r[0] == 'SRX111111' }
    assert_in_delta 10.0, row[4], 0.0001
  end

  # --- default sort: the |Average column, descending, matching production ---

  def test_default_sort_is_average_column_descending
    stub_fetcher(@fixture)
    result = fetch
    ids = result[:rows].map(&:first)
    assert_equal %w[SRX111111 SRX100001 SRX100003 SRX100002], ids
  end

  # --- average column is found by suffix, not hardcoded position ---

  def test_average_column_found_by_suffix_even_if_header_spelling_varies
    fixture = @fixture.sub('Stat3|Average', 'STAT3|Average')
    stub_fetcher(fixture)
    result = fetch
    assert_equal 'STAT3|Average', result[:columns][3]
    assert_equal %w[SRX111111 SRX100001 SRX100003 SRX100002], result[:rows].map(&:first)
  end

  def test_average_column_falls_back_to_fixed_position_without_the_suffix
    fixture = @fixture.sub('Stat3|Average', 'Stat3_mean')
    stub_fetcher(fixture)
    result = fetch
    assert_equal 'Stat3_mean', result[:columns][3]
    # still sorts by column 3 (the fixed fallback position)
    assert_equal %w[SRX111111 SRX100001 SRX100003 SRX100002], result[:rows].map(&:first)
  end

  # --- missing vs malformed ---

  def test_missing_combination_returns_nil
    stub_fetcher(nil)
    assert_nil fetch
  end

  def test_malformed_body_with_too_few_columns_raises_parse_error
    stub_fetcher("Experiment\tCell_subclass\tProtein\n")
    assert_raises(ChipAtlas::ColoTsv::ParseError) { fetch }
  end

  def test_empty_body_raises_parse_error
    stub_fetcher('')
    assert_raises(ChipAtlas::ColoTsv::ParseError) { fetch }
  end

  # --- a short/long data row is padded/truncated to the header's width,
  # not raised on (one bad line must not take down the whole matrix) ---

  def test_short_data_row_is_padded_to_header_width
    fixture = "#{@fixture}SRX999999\tCellZ\tStat3\n"
    stub_fetcher(fixture)
    row = fetch[:rows].find { |r| r[0] == 'SRX999999' }
    assert_equal 7, row.size
    assert_equal 0.0, row[3]
  end

  # --- never touches the network unless a fetcher is stubbed ---

  def test_raises_if_unstubbed_under_test
    assert_raises(ChipAtlas::ColoTsv::LiveFetchNotStubbed) { fetch }
  end
end
