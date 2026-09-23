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

  def test_jobs_available_reports_diff_analysis_available_when_wabi_is_reachable
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/jobs/available', type: 'diff_analysis'
    end
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal true, data['available']
    assert_equal 'wabi', data['backend']
  end

  def test_jobs_available_reports_diff_analysis_unavailable_when_wabi_is_down
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
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

  def test_jobs_submit_503s_for_diff_analysis_when_wabi_is_down
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
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

  def test_jobs_submit_succeeds_and_the_server_merged_diff_analysis_operational_fields
    captured = nil
    ChipAtlas::WabiService.poster = lambda { |params|
      captured = params
      "requestId\tABC123\n"
    }
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      post_json '/jobs/submit', { type: 'diff_analysis', params: { genome: 'hg38', antigenClass: 'dmr' } }
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

  # --- review round (D12 minor #1): the `case` in /jobs/submit must fail
  # closed, not fall through to an empty 200 that reads as "job submitted"
  # ---

  def test_jobs_submit_fails_closed_with_500_if_compute_router_ever_returns_an_unrecognized_shape
    stub_module_method(ChipAtlas::ComputeRouter, :submit, { error: :something_new_and_unexpected }) do
      post_json '/jobs/submit', { type: 'enrichment_analysis', params: { genome: 'hg38' } }
    end
    assert_equal 500, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 'Unexpected compute router response', data['error']
  end

  # --- review round (D12 minor #2), corrected in Task 6 fix round 1: pin
  # what an unrecognized antigenClass does on the full route, not just
  # inside WabiService (see wabi_service_test.rb for the unit-level
  # assertions on the message itself). This used to assert
  # `assert_raises(ChipAtlas::WabiService::UnknownAntigenClass)`, which only
  # pinned Sinatra's test-mode `raise_errors` behaviour (on by default under
  # RACK_ENV=test) -- outside of tests, with diff_analysis now routed to
  # WABI, the same raise would have gone unhandled and reached Sinatra's own
  # error handling (an interactive backtrace page in development, a bare 500
  # in production) on a documented public endpoint. routes/jobs.rb now
  # rescues this and halts 400, so this asserts the real HTTP response. ---

  def test_jobs_submit_400s_for_diff_analysis_with_an_unrecognized_antigen_class
    ChipAtlas::WabiService.poster = ->(_params) { flunk 'must not reach the poster -- the raise happens before posting' }
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      post_json '/jobs/submit', { type: 'diff_analysis', params: { genome: 'hg38', antigenClass: 'bogus' } }
    end
    assert_equal 400, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_includes data['error'], 'diffbind'
    assert_includes data['error'], 'dmr'
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
  # --- GET /jobs/:id/result: the job type selects the URL shape ---

  def test_result_route_returns_html_and_tsv_for_an_enrichment_job
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/jobs/wabi_chipatlas_ID/result?backend=wabi&type=enrichment_analysis'
    end

    assert_equal 200, last_response.status
    urls = JSON.parse(last_response.body)['urls']
    assert_equal %w[html tsv], urls.keys.sort
    assert_includes urls['html'], 'format=html'
    assert_includes urls['tsv'], 'format=tsv'
  end

  def test_result_route_returns_a_zip_for_a_diff_job
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/jobs/wabi_chipatlas_ID/result?backend=wabi&type=diff_analysis'
    end

    assert_equal 200, last_response.status
    urls = JSON.parse(last_response.body)['urls']
    assert_equal ['zip'], urls.keys
    assert_includes urls['zip'], 'format=zip'
  end

  def test_result_route_defaults_to_enrichment_when_type_is_omitted
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/jobs/wabi_chipatlas_ID/result?backend=wabi'
    end

    assert_equal 200, last_response.status
    assert_equal %w[html tsv], JSON.parse(last_response.body)['urls'].keys.sort
  end

  def test_result_route_400s_on_an_unrecognized_job_type
    # Rejected rather than silently treated as an enrichment analysis, which
    # would hand back links to files the job never produced.
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      get '/jobs/wabi_chipatlas_ID/result?backend=wabi&type=colo'
    end

    assert_equal 400, last_response.status
    assert_equal 'Invalid job type', JSON.parse(last_response.body)['error']
  end

  # --- task 5: GET /jobs/:id/result does not gate on backend availability --
  # the URLs are built from the id and backend name alone (ComputeRouter
  # .result_urls makes no network call), and production always shows this
  # text so a user can note the URL down even while the supercomputer is
  # unreachable (DA-31/EA-41). Unlike /status and /log, this route has no
  # `unless backend_available?` check at all. ---

  def test_result_route_succeeds_even_when_the_backend_is_down
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
      get '/jobs/abc/result?backend=wabi&type=diff_analysis'
    end

    assert_equal 200, last_response.status
    urls = JSON.parse(last_response.body)['urls']
    assert_includes urls['zip'], 'format=zip'
  end

  # --- GET /jobs/:id/status: nil from the backend is "unknown", not "running" ---

  def test_status_route_reports_unknown_when_the_backend_status_cannot_be_determined
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      stub_module_method(ChipAtlas::WabiService, :job_status, nil) do
        get '/jobs/wabi_chipatlas_ID/status?backend=wabi'
      end
    end

    assert_equal 200, last_response.status
    assert_equal 'unknown', JSON.parse(last_response.body)['status']
  end

  def test_status_route_passes_wabis_finished_through
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      stub_module_method(ChipAtlas::WabiService, :job_status, 'finished') do
        get '/jobs/wabi_chipatlas_ID/status?backend=wabi'
      end
    end

    assert_equal 'finished', JSON.parse(last_response.body)['status']
  end
end
