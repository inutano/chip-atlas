# frozen_string_literal: true

require_relative '../test_helper'

class BedExtensionResolverTest < Minitest::Test
  BASE = 'https://chip-atlas.dbcls.jp/data'

  def teardown
    ChipAtlas::BedExtensionResolver.prober = nil
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
end
