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

          result = ChipAtlas::ComputeRouter.submit(job_type, data['params'] || data)
          if result
            log_activity('job_submit', { type: job_type, backend: result[:backend], job_id: result[:job_id] })
            json_response(result)
          else
            halt 503, json_response({ error: 'No compute backend available' })
          end
        end

        # Check job status
        app.get '/jobs/:id/status' do
          id = validated_job_id
          backend = validated_backend
          status = ChipAtlas::ComputeRouter.status(backend, id)
          json_response({ backend: backend, job_id: id, status: status || 'unknown' })
        end

        # Get result URLs
        app.get '/jobs/:id/result' do
          id = validated_job_id
          backend = validated_backend
          urls = ChipAtlas::ComputeRouter.result_urls(backend, id)
          json_response({ backend: backend, job_id: id, urls: urls })
        end

        # Get execution log
        app.get '/jobs/:id/log' do
          id = validated_job_id
          backend = validated_backend
          log = ChipAtlas::ComputeRouter.log(backend, id)
          if log
            content_type 'text/plain'
            log
          else
            halt 404, 'Log not available yet'
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
