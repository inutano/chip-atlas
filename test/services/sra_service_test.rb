# frozen_string_literal: true

require_relative '../test_helper'

# SV-34: a failed NCBI lookup used to be cached for SraCache::TTL_SECONDS (30
# days) because fetch_from_ncbi returned error_metadata (a truthy Hash) on
# failure, and fetch cached whatever it got back as long as it was truthy.
# Every test here stubs ChipAtlas::SraService.http_get= so no HTTP request
# ever leaves the process; the last test proves that forgetting to stub is
# impossible to do silently (mirrors ColoTsv/TargetGenesTsv/DataProxy/
# WabiService's LiveFetchNotStubbed/LiveSubmitNotStubbed pattern).
class SraServiceTest < Minitest::Test
  include TestHelper

  ESEARCH_SUCCESS = JSON.generate('esearchresult' => { 'idlist' => ['12345'] })

  EFETCH_SUCCESS = <<~XML
    <EXPERIMENT_PACKAGE_SET>
      <EXPERIMENT_PACKAGE>
        <LIBRARY_NAME>Test Lib</LIBRARY_NAME>
        <LIBRARY_STRATEGY>ChIP-Seq</LIBRARY_STRATEGY>
        <LIBRARY_SOURCE>GENOMIC</LIBRARY_SOURCE>
        <LIBRARY_SELECTION>ChIP</LIBRARY_SELECTION>
        <LIBRARY_CONSTRUCTION_PROTOCOL>Protocol text</LIBRARY_CONSTRUCTION_PROTOCOL>
        <INSTRUMENT_MODEL>Illumina HiSeq 2000</INSTRUMENT_MODEL>
        <PLATFORM><ILLUMINA/></PLATFORM>
        <LIBRARY_LAYOUT><SINGLE/></LIBRARY_LAYOUT>
      </EXPERIMENT_PACKAGE>
    </EXPERIMENT_PACKAGE_SET>
  XML

  def teardown
    ChipAtlas::SraService.http_get = nil
    super
  end

  def test_fetch_returns_cached_metadata_without_reaching_ncbi
    seed_sra_cache

    result = ChipAtlas::SraService.new('SRX018625').fetch

    assert_equal 'SRX018625', result[:experiment_id]
    assert_equal 'H3K4me3 ChIP-seq library', result[:library_description][:library_name]
  end

  def test_fetch_stores_a_successful_ncbi_lookup
    ChipAtlas::SraService.http_get = lambda do |url|
      url.include?('esearch.fcgi') ? ESEARCH_SUCCESS : EFETCH_SUCCESS
    end

    result = ChipAtlas::SraService.new('SRX999999').fetch

    assert_equal 'SRX999999', result[:experiment_id]
    assert_equal 'Test Lib', result[:library_description][:library_name]
    assert_equal 'ILLUMINA', result[:platform]
    assert_equal 'SINGLE', result[:library_layout]

    cached = ChipAtlas::SraCache.get('SRX999999')
    refute_nil cached, 'a successful NCBI lookup must be cached'
    assert_equal 'Test Lib', cached[:library_description][:library_name]
  end

  # The regression itself: a failure must never be written to sra_cache, so
  # the next view of the same experiment retries NCBI instead of replaying
  # "ERROR: cannot retrieve data from NCBI" for 30 days.
  def test_fetch_does_not_cache_a_failed_ncbi_lookup
    ChipAtlas::SraService.http_get = ->(_url) { nil } # simulates NCBI unreachable / non-200

    result = ChipAtlas::SraService.new('SRX999998').fetch

    assert_equal 'ERROR: cannot retrieve data from NCBI', result[:library_description][:library_name]
    assert_nil ChipAtlas::SraCache.get('SRX999998'),
               'a failed lookup must not be cached -- the next view should retry NCBI'
  end

  def test_fetch_does_not_cache_a_malformed_ncbi_response
    ChipAtlas::SraService.http_get = lambda do |url|
      url.include?('esearch.fcgi') ? ESEARCH_SUCCESS : 'not xml at all <<<'
    end

    result = ChipAtlas::SraService.new('SRX999997').fetch

    assert_equal 'ERROR: cannot retrieve data from NCBI', result[:library_description][:library_name]
    assert_nil ChipAtlas::SraCache.get('SRX999997')
  end

  # --- never touches the network unless a stub is installed ---

  def test_raises_if_unstubbed_under_test
    assert_raises(ChipAtlas::SraService::LiveFetchNotStubbed) do
      ChipAtlas::SraService.new('SRX000000').fetch
    end
  end
end
