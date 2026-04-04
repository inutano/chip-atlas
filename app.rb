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
require_relative 'lib/middleware/json_body_parser'
require_relative 'routes/health'
require_relative 'routes/api'
require_relative 'routes/pages'
require_relative 'routes/wabi'

class ChipAtlasApp < Sinatra::Base
  use ChipAtlas::JsonBodyParser

  set :erb, escape_html: true
  set :views, File.join(__dir__, 'views')

  register ChipAtlas::Routes::Health
  register ChipAtlas::Routes::Api
  register ChipAtlas::Routes::Wabi
  register ChipAtlas::Routes::Pages

  helpers do
    def json_response(data)
      content_type 'application/json'
      JSON.generate(data)
    end

    def parsed_json
      data = env['parsed_body']
      halt 400, json_response({ error: 'No JSON body' }) unless data
      log_activity(request.path_info, data)
      data
    end

    def log_activity(action, data = nil)
      fields = [Time.now.iso8601, request.ip, action]
      fields << JSON.generate(data) if data
      settings.access_logger.info(fields.join("\t"))
    end
  end

  configure do
    FileUtils.mkdir_p('log')
    access_log = Logger.new('log/access_log', 'daily')
    access_log.formatter = proc { |_, _, _, msg| "#{msg}\n" }
    set :access_logger, access_log
  end

  configure :production do
    set :host_authorization, { permitted_hosts: ['.chip-atlas.org'] }
  end
end
