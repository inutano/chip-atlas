# frozen_string_literal: true

require_relative '../test_helper'

class BedExtensionResolverTest < Minitest::Test
  BASE = 'https://chip-atlas.dbcls.jp/data'

  def teardown
    ChipAtlas::BedExtensionResolver.prober = nil
    ChipAtlas::BedExtensionResolver.allow_live_probe = false
  end

  def test_resolve_prefers_bed_when_live
    ChipAtlas::BedExtensionResolver.prober = ->(url) { url.end_with?('.bed') }
    assert_equal '.bed', ChipAtlas::BedExtensionResolver.resolve('hg38', 'H3K4me3.Blood.05', BASE)
  end

  def test_resolve_falls_back_to_bed_gz_when_bed_is_gone
    ChipAtlas::BedExtensionResolver.prober = ->(url) { url.end_with?('.bed.gz') }
    assert_equal '.bed.gz', ChipAtlas::BedExtensionResolver.resolve('TAIR12', 'His.ALL.05.H3K4me3.AllCell', BASE)
  end

  def test_resolve_caches_per_genome_and_filename
    calls = []
    ChipAtlas::BedExtensionResolver.prober = lambda { |url|
      calls << url
      url.end_with?('.bed')
    }

    3.times { ChipAtlas::BedExtensionResolver.resolve('hg38', 'H3K4me3.Blood.05', BASE) }
    assert_equal 1, calls.size, "expected the probe to run once and then be cached"

    # A different filename is a different cache key and probes again.
    ChipAtlas::BedExtensionResolver.resolve('hg38', 'CTCF.Blood.05', BASE)
    assert_equal 2, calls.size
  end

  def test_resolve_falls_back_to_first_candidate_when_neither_probe_answers
    ChipAtlas::BedExtensionResolver.prober = ->(_url) { false }
    assert_equal '.bed', ChipAtlas::BedExtensionResolver.resolve('mm10', 'Nonexistent.05', BASE)
  end

  # --- item 1: forgetting to stub must fail loudly, not reach the network ---

  def test_raises_instead_of_reaching_the_network_when_unstubbed_under_test
    ChipAtlas::BedExtensionResolver.prober = nil
    assert_raises(ChipAtlas::BedExtensionResolver::LiveProbeNotStubbed) do
      ChipAtlas::BedExtensionResolver.resolve('hg38', 'ShouldNotHitNetwork.05', BASE)
    end
  end

  def test_allow_live_probe_opts_out_of_the_test_guard
    ChipAtlas::BedExtensionResolver.prober = nil
    ChipAtlas::BedExtensionResolver.allow_live_probe = true

    # A non-archive host is rejected before any real HTTP call is made (see
    # #live?'s host check), so this still never touches the network -- it
    # only proves the opt-in suppresses the raise from item 1's guard.
    extension = ChipAtlas::BedExtensionResolver.resolve('hg38', 'X', 'https://example.invalid/data')
    assert_equal '.bed', extension
  end

  # --- item 2: a confirmed hit and an assumed fallback must not share a TTL ---

  def test_confirmed_result_outlives_the_assumed_ttl
    calls = []
    ChipAtlas::BedExtensionResolver.prober = lambda { |url| calls << url; url.end_with?('.bed') }

    ChipAtlas::BedExtensionResolver.resolve('hg38', 'Confirmed.05', BASE)
    assert_equal 1, calls.size

    # Age the cached entry past ASSUMED_TTL but still well inside
    # CONFIRMED_TTL: a confirmed answer must not be treated as stale yet.
    age_cache_entry('hg38/Confirmed.05', ChipAtlas::BedExtensionResolver::ASSUMED_TTL + 1)
    ChipAtlas::BedExtensionResolver.resolve('hg38', 'Confirmed.05', BASE)
    assert_equal 1, calls.size, 'a confirmed result must not expire on the (short) assumed TTL'
  end

  def test_assumed_fallback_expires_quickly_so_the_next_request_retries
    calls = []
    ChipAtlas::BedExtensionResolver.prober = lambda { |url| calls << url; false }

    ChipAtlas::BedExtensionResolver.resolve('hg38', 'Assumed.05', BASE)
    assert_equal 2, calls.size # both candidates probed once, neither confirmed

    age_cache_entry('hg38/Assumed.05', ChipAtlas::BedExtensionResolver::ASSUMED_TTL + 1)
    ChipAtlas::BedExtensionResolver.resolve('hg38', 'Assumed.05', BASE)
    assert_equal 4, calls.size, 'an unconfirmed fallback must be retried soon, not cached for the full TTL'
  end

  # --- item 3: the cache is bounded, not just TTL-limited ---

  def test_cache_is_bounded_with_fifo_eviction
    ChipAtlas::BedExtensionResolver.prober = ->(_url) { true }
    max = ChipAtlas::BedExtensionResolver::MAX_CACHE_ENTRIES

    (max + 5).times { |i| ChipAtlas::BedExtensionResolver.resolve('hg38', "F#{i}.05", BASE) }

    cache = ChipAtlas::BedExtensionResolver.instance_variable_get(:@cache)
    assert_operator cache.size, :<=, max, 'cache must never grow past MAX_CACHE_ENTRIES'
    refute cache.key?('hg38/F0.05'), 'the earliest entry should have been evicted first (FIFO)'
    assert cache.key?("hg38/F#{max + 4}.05"), 'the most recent entry should still be cached'
  end

  private

  def age_cache_entry(key, seconds)
    cache = ChipAtlas::BedExtensionResolver.instance_variable_get(:@cache)
    cache.fetch(key)[:cached_at] = Time.now - seconds
  end
end
