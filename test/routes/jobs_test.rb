# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../app'

# Never submit a real job — WabiService.poster is stubbed everywhere a
# submission actually goes through, and ServiceMonitor's network probe is
# stubbed via Object#stub so these tests don't depend on real reachability
# of WABI/WES (script/dev/test.sh also runs with --network none as a
# backstop).
class JobsTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    ChipAtlasApp
  end

  def teardown
    ChipAtlas::WabiService.poster = nil
    super
  end

  def post_json(path, body)
    post path, JSON.generate(body), { 'CONTENT_TYPE' => 'application/json' }
  end

  # --- task C3: /jobs/available is honest per job type ---

  def test_jobs_available_reports_diff_analysis_unavailable_even_when_wabi_is_reachable
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/jobs/available', type: 'diff_analysis'
    end
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal false, data['available']
    assert_nil data['backend']
  end

  def test_jobs_available_reports_enrichment_analysis_available_when_wabi_is_reachable
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/jobs/available', type: 'enrichment_analysis'
    end
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal true, data['available']
    assert_equal 'wabi', data['backend']
  end

  # --- task C3: the two submit failure modes are distinguishable over HTTP ---

  def test_jobs_submit_503s_with_a_distinct_message_when_no_backend_is_available
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
      post_json '/jobs/submit', { type: 'enrichment_analysis', params: { genome: 'hg38' } }
    end
    assert_equal 503, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 'No compute backend available', data['error']
  end

  def test_jobs_submit_503s_for_diff_analysis_because_no_backend_serves_it_regardless_of_wabi_health
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      post_json '/jobs/submit', { type: 'diff_analysis', params: { genome: 'hg38', antigenClass: 'diffbind' } }
    end
    assert_equal 503, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 'No compute backend available', data['error']
  end

  def test_jobs_submit_502s_with_a_distinct_message_when_the_backend_rejects_the_submission
    ChipAtlas::WabiService.poster = ->(_params) { nil } # backend reachable, but no requestId parsed
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      post_json '/jobs/submit', { type: 'enrichment_analysis', params: { genome: 'hg38' } }
    end
    assert_equal 502, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 'Compute backend rejected the submission', data['error']
    # This must read differently than the 503 case above -- that's the whole point of C3.
    refute_equal 'No compute backend available', data['error']
  end

  # --- task C2: WabiService merges the operational fields at submission time ---

  # diff_analysis maps to no backends today (ComputeRouter::JOB_TYPE_BACKENDS
  # -- task C3, modelling that WABI does not currently serve it), so a plain
  # POST here would 503 before ever reaching WabiService. Temporarily give
  # diff_analysis a backend to exercise the full route -> ComputeRouter ->
  # WabiService merge for the day that map is updated.
  def test_jobs_submit_succeeds_and_the_server_merged_diff_analysis_operational_fields
    captured = nil
    ChipAtlas::WabiService.poster = lambda { |params|
      captured = params
      "requestId\tABC123\n"
    }
    stub_const(ChipAtlas::ComputeRouter, :JOB_TYPE_BACKENDS, { 'diff_analysis' => ['wabi'] }) do
      stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
        post_json '/jobs/submit', { type: 'diff_analysis', params: { genome: 'hg38', antigenClass: 'dmr' } }
      end
    end

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'wabi', data['backend']
    assert_equal 'ABC123', data['job_id']

    assert_equal '', captured['address']
    assert_equal 'text', captured['format']
    assert_equal 'www', captured['result']
    assert_equal '-p epyc -t 180', captured['sbatchOptions']
    assert_equal 'empty', captured['cellClass']
    assert_equal 'srx', captured['typeA']
    assert_equal 'srx', captured['typeB']
    assert_equal 1, captured['permTime']
    assert_equal 999, captured['threshold'] # dmr
  end

  def test_jobs_submit_succeeds_and_the_server_merged_enrichment_analysis_operational_fields_only
    captured = nil
    ChipAtlas::WabiService.poster = lambda { |params|
      captured = params
      "requestId\tXYZ\n"
    }
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      post_json '/jobs/submit', {
        type: 'enrichment_analysis',
        params: { genome: 'hg38', antigenClass: 'Histone', cellClass: 'Blood', typeA: 'bed', typeB: 'rnd', threshold: '50' },
      }
    end

    assert last_response.ok?
    assert_equal '', captured['address']
    assert_equal 'text', captured['format']
    assert_equal 'www', captured['result']
    assert_equal '-p epyc -t 180', captured['sbatchOptions']

    # user-facing fields on enrichment must pass through untouched, not be
    # overridden by diff analysis's operational constants for the same keys.
    assert_equal 'Blood', captured['cellClass']
    assert_equal 'bed', captured['typeA']
    assert_equal 'rnd', captured['typeB']
    assert_equal '50', captured['threshold']
  end
end
