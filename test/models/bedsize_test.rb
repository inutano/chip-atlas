# frozen_string_literal: true

require_relative '../test_helper'

class BedsizeTest < Minitest::Test
  include TestHelper

  def setup
    seed_bedsizes
  end

  def test_dump
    result = ChipAtlas::Bedsize.dump

    assert_kind_of Hash, result
    assert_equal 150_000, result['hg38,Histone,Blood,05']
    assert_equal 80_000, result['hg38,Histone,Brain,05']
  end

  def test_dump_empty
    DB[:bedsizes].delete
    result = ChipAtlas::Bedsize.dump

    assert_kind_of Hash, result
    assert_empty result
  end
end
