# frozen_string_literal: true

require_relative 'app'
use Rack::RewindableInput::Middleware
run ChipAtlasApp
