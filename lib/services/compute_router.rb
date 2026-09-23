# frozen_string_literal: true

module ChipAtlas
  # Routes analysis jobs to the available compute backend.
  #
  # Enrichment analysis: WABI (primary) → Sapporo/WES (fallback) → unavailable
  # Diff analysis:       WABI (only) → unavailable
  module ComputeRouter
    # Which backends can serve each job type, in priority order. This is
    # deliberately code, not config (per the project owner, task C3/D12):
    # backend routing changes when the app is deployed, not at runtime.
    #
    # A job type mapped to no backends is unavailable regardless of any
    # backend's health check — this map is the single deploy-time switch for
    # which backend(s) a job type may use, independent of whether a given
    # backend happens to be reachable right now. Before this map existed,
    # #available_backend ignored job_type entirely and routed every job type
    # to WABI whenever WABI was merely reachable, so /status could report a
    # job type "ok" and /jobs/available could offer a live backend for a job
    # type WABI does not actually accept.
    #
    # 'diff_analysis' was mapped to no backends here from launch until
    # 2026-09-24: WABI was believed not to serve diff-analysis jobs at all.
    # The project owner confirmed on 2026-09-24 that WABI serves them again
    # and asked for this map to route diff_analysis to it (see
    # docs/review-2026-09-23/findings/ui-diff-analysis.md, DA-01). WES has
    # never served diff analysis (it is enrichment-analysis-only), so WABI
    # is diff analysis's only entry rather than one end of a fallback pair.
    JOB_TYPE_BACKENDS = {
      'enrichment_analysis' => %w[wabi wes].freeze,
      'diff_analysis'       => %w[wabi].freeze,
    }.freeze

    module_function

    # Returns { backend:, available: } or { backend: nil, available: false }
    def available_backend(job_type)
      (JOB_TYPE_BACKENDS[job_type] || []).each do |backend|
        case backend
        when 'wabi'
          return { backend: 'wabi', available: true } if ChipAtlas::ServiceMonitor.status(:wabi)
        when 'wes'
          return { backend: 'wes', available: true } if ChipAtlas::ServiceMonitor.status(:wes)
        end
      end
      { backend: nil, available: false }
    end

    # Submit a job. Returns one of:
    #   { backend:, job_id: }            success
    #   { error: :backend_unavailable }  no backend serves this job type / is up
    #   { error: :submission_rejected }  a backend was reached but rejected the job
    #                                     (e.g. WabiService couldn't parse a
    #                                     requestId out of the response)
    # These two error cases used to both collapse into a bare nil, making
    # "the backend is down" indistinguishable from "the backend rejected
    # this job" to both the caller and whoever is debugging it.
    def submit(job_type, params)
      route = available_backend(job_type)
      return { error: :backend_unavailable } unless route[:available]

      job_id = case route[:backend]
               when 'wabi' then ChipAtlas::WabiService.submit_job(job_type, params)
               when 'wes'  then ChipAtlas::SapporoService.submit_job(params)
               end

      job_id ? { backend: route[:backend], job_id: job_id } : { error: :submission_rejected }
    end

    # Check job status. Returns the backend's own status word ("finished",
    # "running", ...) or nil when it could not be determined.
    def status(backend, job_id)
      case backend
      when 'wabi' then ChipAtlas::WabiService.job_status(job_id)
      when 'wes'  then ChipAtlas::SapporoService.job_status(job_id)
      end
    end

    # Get result URLs. Returns { html:, tsv: } / { zip: } or nil.
    #
    # The shape depends on the job type, not just the backend: an enrichment
    # analysis produces a browsable HTML table and a TSV of the same rows,
    # while a diff analysis produces a zip archive. Production's two result
    # pages reflect exactly that -- "Result URL" + "Download TSV" on one,
    # a single "Download Result" on the other.
    def result_urls(backend, job_id, job_type = 'enrichment_analysis')
      case backend
      when 'wabi'
        base = "https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/#{job_id}?info=result"
        if job_type == 'diff_analysis'
          { zip: "#{base}&format=zip" }
        else
          { html: "#{base}&format=html", tsv: "#{base}&format=tsv" }
        end
      when 'wes'
        {
          html: ChipAtlas::SapporoService.result_url(job_id),
          tsv:  ChipAtlas::SapporoService.result_tsv_url(job_id),
        }
      end
    end

    # Get execution log. Returns string or nil.
    def log(backend, job_id)
      case backend
      when 'wabi' then ChipAtlas::WabiService.fetch_log(job_id)
      when 'wes'  then ChipAtlas::SapporoService.fetch_log(job_id)
      end
    end
  end
end
