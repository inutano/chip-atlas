# frozen_string_literal: true

require_relative 'test_helper'

class SerializersTest < Minitest::Test
  def test_classification_item
    result = ChipAtlas::Serializers.classification_item('Blood', 120)
    assert_equal({ id: 'Blood', label: 'Blood', count: 120 }, result)
  end

  def test_classification_item_nil_count
    result = ChipAtlas::Serializers.classification_item('-')
    assert_equal({ id: '-', label: '-', count: nil }, result)
  end
end
