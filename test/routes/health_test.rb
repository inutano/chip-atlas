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

  # --- task C3 (updated 2026-09-24, DA-01): /status must defer to
  # ComputeRouter for diff_analysis rather than reading WABI reachability
  # directly, so this endpoint can't drift from the routing map that
  # actually decides what WABI serves (ComputeRouter::JOB_TYPE_BACKENDS). ---

  def test_status_reports_diff_analysis_ok_when_wabi_is_reachable
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/status'
    end
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'ok', data['features']['diff_analysis']
  end

  def test_status_reports_diff_analysis_unavailable_when_wabi_is_down
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
      get '/status'
    end
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'unavailable', data['features']['diff_analysis']
  end

  # CHIP_ATLAS_PERMITTED_HOSTS widens production's host authorization for a
  # test instance reached by IP (the production block itself only runs under
  # RACK_ENV=production, so the parsing helper is what gets pinned here).
  def test_permitted_hosts_default_and_env_override
    assert_equal ['.chip-atlas.org'], ChipAtlasApp.permitted_hosts_from(nil)
    assert_equal ['.chip-atlas.org'], ChipAtlasApp.permitted_hosts_from(' , ')
    assert_equal ['.chip-atlas.org', '203.0.113.10'], ChipAtlasApp.permitted_hosts_from('.chip-atlas.org, 203.0.113.10')
  end
end
