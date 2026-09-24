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

    # Enrichment analysis: WABI/CWL require permTime on every submission
    # regardless of dataset B's type (enrichment-analysis.cwl declares it
    # `type: int`, not `int?`). The user-facing value wins; this only fills a
    # gap. See DIFF_ANALYSIS_OPERATIONAL_PARAMS for the diff-job equivalent.
    ENRICHMENT_ANALYSIS_DEFAULT_PARAMS = { 'permTime' => 1 }.freeze

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

    # Raised when a diff-analysis submission's antigenClass isn't one of the
    # keys DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS knows how to map to a
    # threshold. A bare KeyError from Hash#fetch would say the same thing
    # but without enough context to debug from a stack trace alone; this
    # names the failure and says what was expected, same as
    # qvalCodeToThreshold (frontend/pages/enrichment-analysis.ts) refusing
    # to guess a threshold for an unparseable qval code rather than
    # forwarding a wrong-encoding value silently.
    UnknownAntigenClass = Class.new(StandardError)

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
      status, body = post(merged)
      request_id = body && body.split("\n").find { |l| l.start_with?('requestId') }&.split(/\s/)&.last
      unless request_id
        # Field *names* only, never values -- bedAFile/bedBFile can carry
        # megabytes of user data, and the response body is truncated for the
        # same reason. `warn` goes to stderr, which is where Puma already
        # writes, so this needs no new logging configuration to show up.
        warn "[wabi] submission rejected: status=#{status.inspect} " \
             "fields=#{merged.keys.sort.inspect} body=#{body.to_s[0, 500].inspect}"
      end
      request_id
    end

    # WABI's own status endpoint. Returns the status word it reports
    # ("finished", "running", ...) or nil when WABI cannot be reached or does
    # not recognise the request ID.
    #
    # This replaced a HEAD request against `?info=result&format=html` whose
    # 200 was taken to mean "finished". WABI answers HEAD with 405 Method Not
    # Allowed, so that test was false for every job in every state: the status
    # was pinned to "running" forever and the result links, which the frontend
    # only renders on a terminal status, never appeared at all.
    def job_status(request_id)
      uri = URI.parse("#{ENDPOINT}#{request_id}?info=status")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.get(uri.request_uri)
      return nil unless response.code == '200'

      parse_status(response.body)
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::HTTPError
      nil
    end

    # `?info=status` answers with a short colon-delimited record:
    #
    #   request-ID: wabi_chipatlas_2026-0922-1049-51-290-755138
    #   status: finished
    #   current-time: 2026-09-22 10:54:07
    #   system-info: 20752202 chipatlas epyc ... COMPLETED 0:0
    #
    # Only the status line is wanted. An unknown request ID comes back as a
    # JSON error body with a 400, which never reaches here. A 200 whose body
    # has no status line yields nil rather than a guess -- the route renders
    # nil as "unknown", which is honest, where "running" would be a claim.
    def parse_status(body)
      line = body.to_s.lines.find { |l| l.start_with?('status:') }
      return nil unless line

      value = line.split(':', 2).last.to_s.strip
      value.empty? ? nil : value
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
      return ENRICHMENT_ANALYSIS_DEFAULT_PARAMS.merge(merged) unless job_type == 'diff_analysis'

      merged = merged.merge(DIFF_ANALYSIS_OPERATIONAL_PARAMS)
      merged['threshold'] = DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS.fetch(params['antigenClass']) do
        raise UnknownAntigenClass,
              "WabiService: diff analysis submitted with antigenClass #{params['antigenClass'].inspect} -- " \
              "expected one of #{DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS.keys.inspect}. Refusing to guess a threshold."
      end
      merged
    end

    # Returns [status, body]. The test stub (#poster=) only ever supplies a
    # body (see its own docstring), so it is wrapped here with a nil status
    # rather than changing that stub's contract for every existing caller.
    def post(params)
      return [nil, @poster.call(params)] if @poster

      raise_if_unstubbed_under_test!

      response = Net::HTTP.post_form(URI.parse(ENDPOINT), params)
      [response.code, response.body]
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
