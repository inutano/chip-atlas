# frozen_string_literal: true

require_relative 'serializers'
require_relative 'models/experiment'
require_relative 'models/bedfile'
require_relative 'models/bedsize'
require_relative 'models/analysis'
require_relative 'models/run'
require_relative 'models/experiment_search'
require_relative 'models/sra_cache'
require_relative 'services/location_service'
require_relative 'services/wabi_service'
require_relative 'services/sapporo_service'
require_relative 'services/compute_router'
require_relative 'services/sra_service'

module ChipAtlas
  VERSION = '2.0.0'
end
