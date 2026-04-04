# frozen_string_literal: true
# :)

require 'bundler/setup'
require 'json'
require 'net/http'
require 'uri'
require 'timeout'
require 'fileutils'
require 'logger'
require 'sinatra/base'

require_relative 'lib/db'

require_relative 'lib/chip_atlas'
require_relative 'routes/health'
require_relative 'routes/api'
require_relative 'routes/pages'
require_relative 'routes/wabi'

class ChipAtlasApp < Sinatra::Base
  set :erb, escape_html: true
  set :views, File.join(__dir__, 'views')

  register ChipAtlas::Routes::Health
  register ChipAtlas::Routes::Api
  register ChipAtlas::Routes::Wabi
  register ChipAtlas::Routes::Pages

  helpers do
    def app_root
      "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}#{env['SCRIPT_NAME']}"
    end

    def json_response(data)
      content_type 'application/json'
      JSON.generate(data)
    end

    def parsed_json
      @parsed_json ||= begin
        request.body.rewind
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        halt 400, json_response({ error: 'Invalid JSON' })
      end
    end
  end

  configure do
    FileUtils.mkdir_p('log')
    set :access_logger, Logger.new('log/access_log', 'daily')
  end

  configure :production do
    set :host_authorization, { permitted_hosts: ['.chip-atlas.org'] }
  end

  before do
    if request.post? && request.content_type&.include?('application/json')
      request.body.rewind
      body_str = request.body.read
      request.body.rewind
      unless body_str.empty?
        begin
          data = JSON.parse(body_str)
          settings.access_logger.info("#{request.ip}\t#{request.path_info}\t#{data}")
        rescue JSON::ParserError
          # not valid JSON, skip logging
        end
      end
    end
  end
end
