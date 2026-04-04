# frozen_string_literal: true

require 'json'

module ChipAtlas
  # Rack middleware: parses JSON request bodies before they reach routes.
  # Parsed data is available via env['parsed_body'].
  # Returns 400 for malformed JSON.
  class JsonBodyParser
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      if request.post? && request.content_type&.include?('application/json')
        body = request.body.read
        request.body.rewind

        unless body.empty?
          begin
            env['parsed_body'] = JSON.parse(body)
          rescue JSON::ParserError
            return [400, { 'content-type' => 'application/json' },
                    ['{"error":"Invalid JSON"}']]
          end
        end
      end

      @app.call(env)
    end
  end
end
