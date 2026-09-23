# frozen_string_literal: true

require 'json'

module ChipAtlas
  # Rack middleware: parses JSON request bodies before they reach routes.
  # Parsed data is available via env['parsed_body'].
  # Returns 400 for malformed JSON, and 400 for well-formed JSON that isn't
  # an object (e.g. a bare array or scalar) -- routes assume parsed_body
  # supports Hash#[] (see app.rb's parsed_json / condition helpers).
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
            parsed = JSON.parse(body)
          rescue JSON::ParserError
            return [400, { 'content-type' => 'application/json' },
                    ['{"error":"Invalid JSON"}']]
          end

          unless parsed.is_a?(Hash)
            return [400, { 'content-type' => 'application/json' },
                    ['{"error":"JSON body must be an object"}']]
          end

          env['parsed_body'] = parsed
        end
      end

      @app.call(env)
    end
  end
end
