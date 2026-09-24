# frozen_string_literal: true

require 'json'

module ChipAtlas
  module Routes
    module Jobs
      def self.registered(app)
        app.helpers do
          def validated_job_id
            id = params[:id]
            halt 400, json_response({ error: 'Invalid job ID' }) unless id&.match?(/\A[\w\-]+\z/)
            id
          end

          def validated_backend
            backend = params[:backend]
            halt 400, json_response({ error: 'Invalid backend' }) unless %w[wabi wes].include?(backend)
            backend
          end

          # Which of the two job types a result request is about. It decides
          # the shape of the result URLs (see ComputeRouter.result_urls), so an
          # unrecognised value is rejected rather than quietly treated as an
          # enrichment analysis and handed back links to files a diff job never
          # produces.
          def validated_job_type
            type = params[:type] || 'enrichment_analysis'
            unless %w[enrichment_analysis diff_analysis].include?(type)
              halt 400, json_response({ error: 'Invalid job type' })
            end
            type
          end

          def backend_available?(backend)
            case backend
            when 'wabi' then ChipAtlas::ServiceMonitor.status(:wabi)
            when 'wes'  then ChipAtlas::ServiceMonitor.status(:wes)
            else false
            end
          end
        end

        # Check which compute backend is available for a given job type
        app.get '/jobs/available' do
          job_type = params[:type] || 'enrichment_analysis'
          json_response(ChipAtlas::ComputeRouter.available_backend(job_type))
        end

        # Submit a job (enrichment_analysis or diff_analysis)
        app.post '/jobs/submit' do
          data = parsed_json
          job_type = data['type'] || 'enrichment_analysis'

          result = begin
            ChipAtlas::ComputeRouter.submit(job_type, data['params'] || data)
          rescue ChipAtlas::WabiService::UnknownAntigenClass => e
            # Diff analysis's antigenClass selects a fixed threshold
            # (WabiService::DIFF_ANALYSIS_THRESHOLD_BY_ANTIGEN_CLASS), and
            # WabiService deliberately raises rather than guessing one for a
            # value it doesn't recognise -- the right place to refuse (see
            # wabi_service.rb). But this is a public HTTP endpoint, and the
            # request supplied the bad value, so it gets an ordinary 400
            # here instead of an unhandled exception reaching Sinatra's own
            # error handling (an interactive backtrace page in development,
            # a bare 500 in production).
            halt 400, json_response({ error: e.message, retry: false })
          end

          case result[:error]
          when nil
            log_activity('job_submit', { type: job_type, backend: result[:backend], job_id: result[:job_id] })
            json_response(result)
          when :backend_unavailable
            halt 503, json_response({ error: 'No compute backend available', retry: false })
          when :submission_rejected
            log_activity('job_submit_rejected', { type: job_type, backend: result[:backend] })
            halt 502, json_response({ error: 'Compute backend rejected the submission', retry: false })
          else
            # ComputeRouter.submit's contract only ever returns nil,
            # :backend_unavailable or :submission_rejected (see
            # lib/services/compute_router.rb) -- this branch should be
            # unreachable. It exists so that if that contract is ever
            # violated, this route fails closed with a 500 instead of
            # falling through Sinatra's `case` with no halt/json_response,
            # which would otherwise send the client an empty 200 that reads
            # as "job submitted" for a submission that never happened.
            halt 500, json_response({ error: 'Unexpected compute router response', retry: false })
          end
        end

        # Check job status — fails fast if backend is known to be down
        app.get '/jobs/:id/status' do
          id = validated_job_id
          backend = validated_backend

          unless backend_available?(backend)
            halt 503, json_response({
              backend: backend, job_id: id,
              status: 'backend_unavailable', retry: false,
            })
          end

          status = ChipAtlas::ComputeRouter.status(backend, id)
          json_response({ backend: backend, job_id: id, status: status || 'unknown', retry: true })
        end

        # Get result URLs -- no backend-availability gate, unlike :status and
        # :log below. ComputeRouter.result_urls builds these from the id and
        # backend name alone (no network call), so they are exactly as
        # available when the backend is down as when it is up, and production
        # always shows this text so a user can note the URL down while the
        # supercomputer is unreachable (DA-31/EA-41).
        app.get '/jobs/:id/result' do
          id = validated_job_id
          backend = validated_backend

          urls = ChipAtlas::ComputeRouter.result_urls(backend, id, validated_job_type)
          json_response({ backend: backend, job_id: id, urls: urls })
        end

        # Get execution log
        app.get '/jobs/:id/log' do
          id = validated_job_id
          backend = validated_backend

          # Finding 4 (2026-09-24 final review): a plain-string halt body
          # here (unlike every other error in this file) has its content
          # type default to text/html, which routes/pages.rb's `not_found`
          # handler then replaces outright with the site's HTML 404 page for
          # the 404 case (it only leaves a halt's body alone when it is
          # already JSON) -- so a client asking for this log over JSON got
          # an HTML page back. json_response matches the sibling routes
          # above (:status, :result) and keeps the not_found guard's
          # content-type check satisfied.
          unless backend_available?(backend)
            halt 503, json_response({ error: 'Backend unavailable', retry: false })
          end

          log = ChipAtlas::ComputeRouter.log(backend, id)
          if log
            content_type 'text/plain'
            log
          else
            halt 404, json_response({ error: 'Log not available yet' })
          end
        end

        # Estimated runtime for diff analysis
        app.post '/jobs/estimated_time' do
          data = parsed_json
          total_reads = ChipAtlas::Experiment.total_number_of_reads(data['ids']).to_i
          seconds = case data['analysis']
                    when 'dmr'      then 117.13 * Math.log(total_reads) - 2012.5 + 600
                    when 'diffbind' then 1.80e-6 * total_reads + 119.38 + 600
                    end
          minutes = (seconds && !seconds.infinite?) ? Rational(seconds, 60).to_f.round : nil
          json_response({ minutes: minutes })
        end
      end
    end
  end
end
