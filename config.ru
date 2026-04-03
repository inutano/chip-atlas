# frozen_string_literal: true

require File.dirname(__FILE__) + '/app'
use Rack::RewindableInput::Middleware
run ChipAtlasApp
