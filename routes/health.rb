# frozen_string_literal: true

module ChipAtlas
  module Routes
    module Health
      def self.registered(app)
        # Internal health check (for load balancers, deployment scripts)
        app.get '/health' do
          checks = {}

          begin
            DB.test_connection
            checks[:database] = 'ok'
          rescue Sequel::DatabaseError => e
            checks[:database] = 'error'
            checks[:database_error] = e.message
          end

          checks[:experiments] = DB[:experiments].count > 0 ? 'ok' : 'empty'

          healthy = checks[:database] == 'ok'
          status healthy ? 200 : 503
          json_response({ status: healthy ? 'ok' : 'error', checks: checks })
        end

        # External service status (for frontend to show alerts and disable features)
        app.get '/status' do
          cache_control :public, max_age: 30
          json_response(ChipAtlas::ServiceMonitor.all_statuses)
        end
      end
    end
  end
end
