# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../app'

class HealthTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

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

  # --- task C3: /status must not report diff_analysis "ok" just because
  # WABI itself is reachable -- WABI does not currently serve diff-analysis
  # jobs at all (ComputeRouter::JOB_TYPE_BACKENDS), independent of health. ---

  def test_status_reports_diff_analysis_unavailable_even_when_wabi_is_reachable
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/status'
    end
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'unavailable', data['features']['diff_analysis']
  end

  def test_status_reports_diff_analysis_unavailable_when_wabi_is_down_too
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
      get '/status'
    end
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'unavailable', data['features']['diff_analysis']
  end
end
