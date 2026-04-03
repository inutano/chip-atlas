module ChipAtlas
  module Routes
    module Health
      def self.registered(app)
        app.get '/health' do
          checks = {}

          begin
            DB.execute("SELECT 1")
            checks[:database] = 'ok'
          rescue => e
            checks[:database] = 'error'
            checks[:database_error] = e.message
          end

          config_loaded = begin
            settings.respond_to?(:list_of_genome) && settings.list_of_genome
          rescue
            false
          end
          checks[:config] = config_loaded ? 'ok' : 'not_loaded'

          healthy = checks[:database] == 'ok'
          status healthy ? 200 : 503
          content_type 'application/json'
          JSON.generate({ status: healthy ? 'ok' : 'error', checks: checks })
        end
      end
    end
  end
end
