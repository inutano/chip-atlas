# frozen_string_literal: true

module ChipAtlas
  module Serializers
    module_function

    def classification_item(id, count = nil)
      { id: id, label: id, count: count }
    end
  end
end
