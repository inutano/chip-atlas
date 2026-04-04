# frozen_string_literal: true

module ChipAtlas
  # Routes analysis jobs to the available compute backend.
  #
  # Enrichment analysis: WABI (primary) → Sapporo/WES (fallback) → unavailable
  # Diff analysis:       WABI (primary) → unavailable
  module ComputeRouter
    module_function

    # Returns { backend:, available: } or { backend: nil, available: false }
    def available_backend(job_type)
      if ChipAtlas::ServiceMonitor.status(:wabi)
        { backend: 'wabi', available: true }
      elsif job_type == 'enrichment_analysis' && ChipAtlas::ServiceMonitor.status(:wes)
        { backend: 'wes', available: true }
      else
        { backend: nil, available: false }
      end
    end

    # Submit a job. Returns { backend:, job_id: } or nil.
    def submit(job_type, params)
      route = available_backend(job_type)
      return nil unless route[:available]

      case route[:backend]
      when 'wabi'
        job_id = ChipAtlas::WabiService.submit_job(params)
        job_id ? { backend: 'wabi', job_id: job_id } : nil
      when 'wes'
        job_id = ChipAtlas::SapporoService.submit_job(params)
        job_id ? { backend: 'wes', job_id: job_id } : nil
      end
    end

    # Check job status. Returns "finished", "running", "error", or nil.
    def status(backend, job_id)
      case backend
      when 'wabi' then ChipAtlas::WabiService.job_finished?(job_id) ? 'finished' : 'running'
      when 'wes'  then ChipAtlas::SapporoService.job_status(job_id)
      end
    end

    # Get result URLs. Returns { html:, tsv:, ... } or nil.
    def result_urls(backend, job_id)
      case backend
      when 'wabi'
        base = "https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/#{job_id}?info=result"
        { html: "#{base}&format=html", tsv: "#{base}&format=tsv" }
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
