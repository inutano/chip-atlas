# frozen_string_literal: true

module ChipAtlas
  # Routes analysis jobs to the available compute backend.
  #
  # Enrichment analysis: WABI (primary) → Sapporo/WES (fallback) → unavailable
  # Diff analysis:       WABI (primary) → unavailable
  module ComputeRouter
    # Which backends can serve each job type, in priority order. This is
    # deliberately code, not config (per the project owner, task C3/D12):
    # backend routing changes when the app is deployed, not at runtime.
    #
    # A job type mapped to no backends is unavailable regardless of any
    # backend's health check — this is how "WABI does not currently serve
    # diff analysis" (a fact about what WABI accepts, independent of whether
    # WABI itself is reachable) gets modelled. Before this map existed,
    # #available_backend ignored job_type entirely and routed every job type
    # to WABI whenever WABI was merely reachable, so /status reported
    # "diff_analysis":"ok" and /jobs/available offered a live backend while
    # every diff-analysis submission actually failed.
    JOB_TYPE_BACKENDS = {
      'enrichment_analysis' => %w[wabi wes].freeze,
      'diff_analysis'       => [].freeze,
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
