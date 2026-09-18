# frozen_string_literal: true

require_relative '../test_helper'

# Never submit a real job — see task C2/C3 briefs. Every test here stubs
# ChipAtlas::WabiService.poster= so no HTTP request ever leaves the process;
# the last test proves that forgetting to stub is impossible to do silently.
class WabiServiceTest < Minitest::Test
  def teardown
    ChipAtlas::WabiService.poster = nil
    ChipAtlas::WabiService.allow_live_submit = false
  end

  def test_enrichment_analysis_gets_the_four_common_operational_fields
    captured = capture_submission('enrichment_analysis', {
      'genome' => 'hg38', 'antigenClass' => 'Histone', 'cellClass' => 'Blood',
      'threshold' => '50', 'typeA' => 'bed', 'bedAFile' => "chr1\t1\t100",
      'typeB' => 'rnd', 'permTime' => '1', 'title' => 'My project',
    })

    assert_equal '', captured['address']
    assert_equal 'text', captured['format']
    assert_equal 'www', captured['result']
    assert_equal '-p epyc -t 180', captured['sbatchOptions']
  end

  def test_enrichment_analysis_user_facing_fields_pass_through_untouched
    captured = capture_submission('enrichment_analysis', {
      'genome' => 'hg38', 'antigenClass' => 'Histone', 'cellClass' => 'Blood',
      'threshold' => '50', 'typeA' => 'bed', 'bedAFile' => "chr1\t1\t100",
      'typeB' => 'rnd', 'permTime' => '1', 'title' => 'My project',
    })

    # WabiService must not override any of these — they came from the user's
    # form (enrichment-analysis.ts's buildEnrichmentParams) and diff
    # analysis's operational constants for the same-named fields must not
    # leak onto this job type.
    assert_equal 'Blood', captured['cellClass']
    assert_equal 'bed', captured['typeA']
    assert_equal 'rnd', captured['typeB']
    assert_equal '1', captured['permTime']
    assert_equal '50', captured['threshold']
  end

  def test_enrichment_analysis_does_not_gain_diff_only_fields_it_never_sent
    captured = capture_submission('enrichment_analysis', { 'genome' => 'hg38' })

    refute captured.key?('cellClass'), 'cellClass is user-facing on enrichment; WabiService must not invent it'
    refute captured.key?('typeA')
    refute captured.key?('typeB')
    refute captured.key?('permTime')
    refute captured.key?('threshold')
  end

  def test_diff_analysis_gets_the_four_common_operational_fields
    captured = capture_submission('diff_analysis', {
      'genome' => 'hg38', 'antigenClass' => 'diffbind',
      'bedAFile' => 'SRX000001', 'bedBFile' => 'SRX000002', 'title' => 'diff project',
    })

    assert_equal '', captured['address']
    assert_equal 'text', captured['format']
    assert_equal 'www', captured['result']
    assert_equal '-p epyc -t 180', captured['sbatchOptions']
  end

  def test_diff_analysis_gets_its_own_operational_fields
    captured = capture_submission('diff_analysis', {
      'genome' => 'hg38', 'antigenClass' => 'diffbind',
      'bedAFile' => 'SRX000001', 'bedBFile' => 'SRX000002', 'title' => 'diff project',
    })

    assert_equal 'empty', captured['cellClass']
    assert_equal 'srx', captured['typeA']
    assert_equal 'srx', captured['typeB']
    assert_equal 1, captured['permTime']
  end

  def test_diff_analysis_threshold_is_50_for_diffbind
    captured = capture_submission('diff_analysis', { 'antigenClass' => 'diffbind' })
    assert_equal 50, captured['threshold']
  end

  def test_diff_analysis_threshold_is_999_for_dmr
    captured = capture_submission('diff_analysis', { 'antigenClass' => 'dmr' })
    assert_equal 999, captured['threshold']
  end

  # This threshold has no UI control on either site and must never be
  # conflated with enrichment's user-facing "Threshold for Significance"
  # (qvalCodeToThreshold in enrichment-analysis.ts, task C1/D10).
  def test_diff_analysis_threshold_is_independent_of_any_threshold_the_caller_passed_in
    captured = capture_submission('diff_analysis', { 'antigenClass' => 'diffbind', 'threshold' => '999999' })
    assert_equal 50, captured['threshold'], "diff analysis's operational threshold must win over any caller-supplied value"
  end

  def test_operational_fields_cannot_be_spoofed_by_the_caller
    captured = capture_submission('enrichment_analysis', { 'address' => 'attacker@example.com', 'format' => 'json' })
    assert_equal '', captured['address']
    assert_equal 'text', captured['format']
  end

  # --- review round: pin what an unrecognized antigenClass does (D12 minor #2) ---
  #
  # A bare KeyError from DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS.fetch would
  # fail loudly too, but with no context in the message. This is exactly the
  # kind of thing that must be pinned by a test -- an untested "fails loudly"
  # path is how the original qval-as-threshold bug shipped in the first
  # place (see qvalCodeToThreshold's own comment in enrichment-analysis.ts).

  def test_diff_analysis_with_an_unrecognized_antigen_class_raises_a_named_error_instead_of_guessing
    ChipAtlas::WabiService.poster = ->(_params) { flunk 'must not reach the poster -- the raise happens during merge, before posting' }
    error = assert_raises(ChipAtlas::WabiService::UnknownAntigenClass) do
      ChipAtlas::WabiService.submit_job('diff_analysis', { 'antigenClass' => 'not-a-real-experiment-type' })
    end
    assert_match(/not-a-real-experiment-type/, error.message)
    assert_match(/diffbind/, error.message)
    assert_match(/dmr/, error.message)
  end

  def test_diff_analysis_with_a_missing_antigen_class_also_raises
    assert_raises(ChipAtlas::WabiService::UnknownAntigenClass) do
      ChipAtlas::WabiService.submit_job('diff_analysis', { 'genome' => 'hg38' }) # no antigenClass at all
    end
  end

  def test_submit_job_extracts_the_request_id_from_the_wabi_response_body
    ChipAtlas::WabiService.poster = ->(_params) { "someOtherField\tvalue\nrequestId\tABC123\n" }
    job_id = ChipAtlas::WabiService.submit_job('enrichment_analysis', { 'genome' => 'hg38' })
    assert_equal 'ABC123', job_id
  end

  def test_submit_job_returns_nil_when_the_response_has_no_request_id
    ChipAtlas::WabiService.poster = ->(_params) { "error\tsomething went wrong\n" }
    job_id = ChipAtlas::WabiService.submit_job('enrichment_analysis', { 'genome' => 'hg38' })
    assert_nil job_id
  end

  def test_submit_job_returns_nil_when_the_response_body_is_nil
    ChipAtlas::WabiService.poster = ->(_params) { nil }
    job_id = ChipAtlas::WabiService.submit_job('enrichment_analysis', { 'genome' => 'hg38' })
    assert_nil job_id
  end

  # --- never submit a real job: forgetting to stub must fail loudly ---

  def test_raises_instead_of_reaching_the_network_when_unstubbed_under_test
    ChipAtlas::WabiService.poster = nil
    assert_raises(ChipAtlas::WabiService::LiveSubmitNotStubbed) do
      ChipAtlas::WabiService.submit_job('enrichment_analysis', { 'genome' => 'hg38' })
    end
  end

  private

  def capture_submission(job_type, params)
    captured = nil
    ChipAtlas::WabiService.poster = lambda { |merged|
      captured = merged
      "requestId\tSTUBBED\n"
    }
    ChipAtlas::WabiService.submit_job(job_type, params)
    captured
  end
end
