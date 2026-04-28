# frozen_string_literal: true

require_relative '../test_helper'

class SraCacheTest < Minitest::Test
  include TestHelper

  def test_get_returns_nil_for_nonexistent
    assert_nil ChipAtlas::SraCache.get('SRX999999')
  end

  def test_set_then_get
    metadata = { title: 'Test experiment', organism: 'Homo sapiens' }
    ChipAtlas::SraCache.set('SRX000001', metadata)

    result = ChipAtlas::SraCache.get('SRX000001')
    assert_equal 'Test experiment', result[:title]
    assert_equal 'Homo sapiens', result[:organism]
  end

  def test_get_returns_nil_for_expired_entry
    metadata = { title: 'Old experiment' }
    ChipAtlas::SraCache.set('SRX000002', metadata)

    # Manually set fetched_at to 31 days ago to expire the entry
    expired_time = Time.now - (31 * 24 * 60 * 60)
    DB[:sra_cache].where(experiment_id: 'SRX000002').update(fetched_at: expired_time)

    assert_nil ChipAtlas::SraCache.get('SRX000002')
  end

  def test_clear_expired_removes_old_entries
    ChipAtlas::SraCache.set('SRX000003', { title: 'Fresh' })
    ChipAtlas::SraCache.set('SRX000004', { title: 'Stale' })

    # Expire only SRX000004
    expired_time = Time.now - (31 * 24 * 60 * 60)
    DB[:sra_cache].where(experiment_id: 'SRX000004').update(fetched_at: expired_time)

    ChipAtlas::SraCache.clear_expired

    assert_equal 1, DB[:sra_cache].count
    refute_nil ChipAtlas::SraCache.get('SRX000003')
    assert_nil ChipAtlas::SraCache.get('SRX000004')
  end

  def test_set_overwrites_existing
    ChipAtlas::SraCache.set('SRX000005', { title: 'Original' })
    ChipAtlas::SraCache.set('SRX000005', { title: 'Updated' })

    result = ChipAtlas::SraCache.get('SRX000005')
    assert_equal 'Updated', result[:title]
    assert_equal 1, DB[:sra_cache].where(experiment_id: 'SRX000005').count
  end
end
