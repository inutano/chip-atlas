# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../app'

class HealthTest < Minitest::Test
  include Rack::Test::Methods

  def app
    ChipAtlasApp
  end

  def test_health_returns_ok
    get '/health'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'ok', data['status']
    assert_equal 'ok', data['checks']['database']
  end
end
