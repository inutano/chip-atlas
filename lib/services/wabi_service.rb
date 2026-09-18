# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'timeout'

module ChipAtlas
  module WabiService
    ENDPOINT = 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/'

    # Operational fields WABI requires on every submission, regardless of job
    # type. None of these have a UI control on either job-submission page —
    # the frontend deliberately does not build them (see task C1's
    # enrichment-analysis.test.ts / diff-analysis.test.ts, which assert they
    # are absent from the frontend payload) — so they are merged in here,
    # at the point of submission, rather than in routes/jobs.rb or the
    # frontend. Operational values always win over anything a caller passes
    # under the same key.
    COMMON_OPERATIONAL_PARAMS = {
      'address'       => '',    # no email notification
      'format'        => 'text',
      'result'        => 'www',
      'sbatchOptions' => '-p epyc -t 180',
    }.freeze

    # Diff Analysis only. cellClass/typeA/typeB/permTime/threshold are
    # *user-facing* fields on Enrichment Analysis (they come straight through
    # from that page's form — see enrichment-analysis.ts's
    # buildEnrichmentParams) and must NOT be touched there. On Diff Analysis
    # they have no UI control at all; diff-analysis.ts's buildDiffAnalysisParams
    # deliberately leaves them out, same as the common operational fields above.
    DIFF_ANALYSIS_OPERATIONAL_PARAMS = {
      'cellClass' => 'empty',
      'typeA'     => 'srx',
      'typeB'     => 'srx',
      'permTime'  => 1,
    }.freeze

    # Diff Analysis's `threshold` is an operational constant keyed on the
    # experiment type (antigenClass: "diffbind" | "dmr"), not the user-facing
    # "Threshold for Significance" on Enrichment Analysis (task C1, D10) and
    # not wired to it — diff analysis has no threshold control in the UI on
    # either site. Fetch (not []) so an unrecognized antigenClass fails loudly
    # instead of silently guessing a threshold.
    DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS = {
      'diffbind' => 50,
      'dmr'      => 999,
    }.freeze

    # Raised when something would submit a live job to WABI while the process
    # is under test and no stub has been installed. This exists so a test
    # that forgets to stub submission fails loudly instead of silently
    # enqueuing real compute on the shared DDBJ service (see task C3 brief,
    # and BedExtensionResolver's LiveProbeNotStubbed for the same pattern).
    LiveSubmitNotStubbed = Class.new(StandardError)

    TEST_ENV_VALUES = %w[test].freeze

    @poster = nil
    @allow_live_submit = false

    module_function

    # Test-only hook: replace the real HTTP POST with a stub. `callable` is
    # invoked as `callable.call(params)` (the fully-merged params hash) and
    # must return the raw WABI response body (a String) or nil.
    def poster=(callable)
      @poster = callable
    end

    # Explicit opt-in for a test that genuinely wants to submit a live job
    # under RACK_ENV/APP_ENV=test (none should). Without this, #submit_job
    # raises LiveSubmitNotStubbed rather than reaching the network when no
    # poster is set and the environment says "test".
    def allow_live_submit=(value)
      @allow_live_submit = value
    end

    def submit_job(job_type, params)
      merged = merge_operational_params(job_type, params)
      body = post(merged)
      return nil unless body

      body.split("\n").find { |l| l.start_with?('requestId') }&.split(/\s/)&.last
    end

    def job_finished?(request_id)
      uri = URI.parse("#{ENDPOINT}#{request_id}?info=result&format=html")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.request_head(uri.request_uri)
      response.code == '200'
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      nil
    end

    def fetch_log(request_id)
      uri = URI.parse("#{ENDPOINT}#{request_id}?info=result&format=log")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.get(uri.request_uri)
      response.code == '200' ? response.body : nil
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      nil
    end

    def merge_operational_params(job_type, params)
      merged = params.merge(COMMON_OPERATIONAL_PARAMS)
      return merged unless job_type == 'diff_analysis'

      merged = merged.merge(DIFF_ANALYSIS_OPERATIONAL_PARAMS)
      merged['threshold'] = DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS.fetch(params['antigenClass'])
      merged
    end

    def post(params)
      return @poster.call(params) if @poster

      raise_if_unstubbed_under_test!

      response = Net::HTTP.post_form(URI.parse(ENDPOINT), params)
      response.body
    end

    def raise_if_unstubbed_under_test!
      return if @allow_live_submit
      return unless TEST_ENV_VALUES.include?(ENV['RACK_ENV']) || TEST_ENV_VALUES.include?(ENV['APP_ENV'])

      raise LiveSubmitNotStubbed,
            "WabiService would submit a live job to #{ENDPOINT} under " \
            "RACK_ENV=#{ENV['RACK_ENV'].inspect}/APP_ENV=#{ENV['APP_ENV'].inspect}. " \
            'Stub ChipAtlas::WabiService.poster= in this test (or set ' \
            '.allow_live_submit = true if a real submission is intentional).'
    end

    private_class_method :merge_operational_params, :post, :raise_if_unstubbed_under_test!
  end
end
