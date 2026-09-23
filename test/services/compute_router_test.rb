# frozen_string_literal: true

require_relative '../test_helper'

# Never submit a real job — every WabiService call here goes through a
# stubbed poster (see wabi_service_test.rb), and ServiceMonitor's network
# probe is stubbed via Minitest's Object#stub so this suite never depends on
# — or waits on — real reachability of WABI/WES.
class ComputeRouterTest < Minitest::Test
  include TestHelper

  def teardown
    ChipAtlas::WabiService.poster = nil
    super
  end

  # --- task C3: per-job-type availability, driven by JOB_TYPE_BACKENDS ---

  def test_diff_analysis_routes_to_wabi_when_wabi_is_up
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      assert_equal({ backend: 'wabi', available: true }, ChipAtlas::ComputeRouter.available_backend('diff_analysis'))
    end
  end

  def test_diff_analysis_is_unavailable_when_wabi_is_down
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
      assert_equal({ backend: nil, available: false }, ChipAtlas::ComputeRouter.available_backend('diff_analysis'))
    end
  end

  def test_enrichment_analysis_routes_to_wabi_when_wabi_is_up
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      assert_equal({ backend: 'wabi', available: true }, ChipAtlas::ComputeRouter.available_backend('enrichment_analysis'))
    end
  end

  def test_enrichment_analysis_falls_back_to_wes_when_wabi_is_down
    checked = lambda { |service| service == :wes }
    stub_module_method(ChipAtlas::ServiceMonitor, :status, checked) do
      assert_equal({ backend: 'wes', available: true }, ChipAtlas::ComputeRouter.available_backend('enrichment_analysis'))
    end
  end

  def test_enrichment_analysis_unavailable_when_both_backends_are_down
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
      assert_equal({ backend: nil, available: false }, ChipAtlas::ComputeRouter.available_backend('enrichment_analysis'))
    end
  end

  def test_an_unrecognized_job_type_is_unavailable_rather_than_defaulting_to_wabi
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      assert_equal({ backend: nil, available: false }, ChipAtlas::ComputeRouter.available_backend('made_up_job_type'))
    end
  end

  # --- task C3: the two submit failure modes no longer collapse into nil ---

  def test_submit_reports_backend_unavailable_when_no_backend_serves_the_job_type
    result = ChipAtlas::ComputeRouter.submit('diff_analysis', {})
    assert_equal({ error: :backend_unavailable }, result)
  end

  def test_submit_reports_backend_unavailable_when_the_backend_is_down
    stub_module_method(ChipAtlas::ServiceMonitor, :status, false) do
      result = ChipAtlas::ComputeRouter.submit('enrichment_analysis', { 'genome' => 'hg38' })
      assert_equal({ error: :backend_unavailable }, result)
    end
  end

  def test_submit_reports_submission_rejected_when_the_backend_is_reachable_but_wabi_service_cannot_parse_a_request_id
    ChipAtlas::WabiService.poster = ->(_params) { nil }
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      result = ChipAtlas::ComputeRouter.submit('enrichment_analysis', { 'genome' => 'hg38' })
      assert_equal({ error: :submission_rejected }, result)
    end
  end

  def test_submit_returns_backend_and_job_id_on_success
    ChipAtlas::WabiService.poster = ->(_params) { "requestId\tABC123\n" }
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      result = ChipAtlas::ComputeRouter.submit('enrichment_analysis', { 'genome' => 'hg38' })
      assert_equal({ backend: 'wabi', job_id: 'ABC123' }, result)
    end
  end

  # WabiService doesn't expose the job_type it merged with directly, so
  # assert indirectly: diff analysis's operational cellClass ('empty') only
  # appears in the merged params when #submit passed job_type through to
  # WabiService.submit_job as 'diff_analysis' (task C2).
  def test_submit_passes_job_type_through_to_wabi_service_so_it_can_pick_the_right_operational_fields
    captured_cell_class = nil
    ChipAtlas::WabiService.poster = lambda { |params|
      captured_cell_class = params['cellClass']
      "requestId\tABC\n"
    }
    stub_module_method(ChipAtlas::ServiceMonitor, :status, true) do
      ChipAtlas::ComputeRouter.submit('diff_analysis', { 'antigenClass' => 'diffbind' })
    end
    assert_equal 'empty', captured_cell_class
  end
  # --- result URLs: shape depends on the job type, not just the backend ---
  #
  # An enrichment analysis produces a browsable HTML table plus a TSV of the
  # same rows; a diff analysis produces a zip archive. Production's two result
  # pages show exactly that split ("Result URL" + "Download TSV" on one,
  # a single "Download Result" on the other). Handing a diff job html/tsv
  # links points the user at files WABI never wrote for it.

  def test_wabi_enrichment_result_urls_are_the_html_table_and_its_tsv
    urls = ChipAtlas::ComputeRouter.result_urls('wabi', 'wabi_chipatlas_ID', 'enrichment_analysis')

    assert_equal 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/wabi_chipatlas_ID?info=result&format=html', urls[:html]
    assert_equal 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/wabi_chipatlas_ID?info=result&format=tsv', urls[:tsv]
    refute urls.key?(:zip)
  end

  def test_wabi_diff_result_urls_are_a_single_zip
    urls = ChipAtlas::ComputeRouter.result_urls('wabi', 'wabi_chipatlas_ID', 'diff_analysis')

    assert_equal 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/wabi_chipatlas_ID?info=result&format=zip', urls[:zip]
    refute urls.key?(:html), 'a diff job has no HTML result table'
    refute urls.key?(:tsv)
  end

  def test_result_urls_defaults_to_enrichment_when_no_job_type_is_given
    assert_equal ChipAtlas::ComputeRouter.result_urls('wabi', 'ID', 'enrichment_analysis'),
                 ChipAtlas::ComputeRouter.result_urls('wabi', 'ID')
  end

  # --- job status comes from WABI's own status endpoint ---

  def test_wabi_status_reports_whatever_word_wabi_gives
    stub_module_method(ChipAtlas::WabiService, :job_status, 'finished') do
      assert_equal 'finished', ChipAtlas::ComputeRouter.status('wabi', 'ID')
    end
    stub_module_method(ChipAtlas::WabiService, :job_status, 'running') do
      assert_equal 'running', ChipAtlas::ComputeRouter.status('wabi', 'ID')
    end
  end

  def test_wabi_status_is_nil_when_wabi_could_not_be_asked
    # Not "running". An unreachable backend is unknown, and the route turns
    # nil into "unknown" -- claiming "running" is what the old HEAD-based
    # check did for every job in every state, finished ones included.
    stub_module_method(ChipAtlas::WabiService, :job_status, nil) do
      assert_nil ChipAtlas::ComputeRouter.status('wabi', 'ID')
    end
  end
end
