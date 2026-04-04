# frozen_string_literal: true

require 'json'

module ChipAtlas
  module Routes
    module Wabi
      def self.registered(app)
        app.helpers do
          def validated_wabi_id
            id = params[:id]
            halt 400, 'Invalid request ID' unless id&.match?(/\A[\w\-]+\z/)
            id
          end
        end

        app.get '/wabi_endpoint_status' do
          ChipAtlas::WabiService.endpoint_available? ? 'chipatlas' : ''
        end

        app.get '/wabi_chipatlas' do
          id = validated_wabi_id
          result = ChipAtlas::WabiService.job_finished?(id)
          case result
          when true  then 'finished'
          when false then 'running'
          else 'server unavailable'
          end
        end

        app.post '/wabi_chipatlas' do
          unless ChipAtlas::WabiService.endpoint_available?
            halt 503
          end

          post_data = if request.content_type&.include?('application/json')
            request.body.rewind
            JSON.parse(request.body.read)
          else
            params
          end

          request_id = ChipAtlas::WabiService.submit_job(post_data)
          if request_id
            log_activity('wabi_submit', { requestId: request_id })
            json_response({ 'requestId' => request_id })
          else
            json_response({ 'request_body' => post_data.to_s })
          end
        end

        %w[enrichment_analysis_log diff_analysis_log].each do |path|
          app.get "/#{path}" do
            id = validated_wabi_id
            log = ChipAtlas::WabiService.fetch_log(id)
            if log
              log
            else
              status 404
              'Log file not available yet'
            end
          end
        end
      end
    end
  end
end
