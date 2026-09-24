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
require 'kramdown'

require_relative 'lib/db'

require_relative 'lib/chip_atlas'
require_relative 'lib/middleware/json_body_parser'
require_relative 'routes/health'
require_relative 'routes/api'
require_relative 'routes/pages'
require_relative 'routes/jobs'

class ChipAtlasApp < Sinatra::Base
  use ChipAtlas::JsonBodyParser

  set :erb, escape_html: true
  set :views, File.join(__dir__, 'views')

  register ChipAtlas::Routes::Health
  register ChipAtlas::Routes::Api
  register ChipAtlas::Routes::Jobs
  register ChipAtlas::Routes::Pages

  helpers do
    # Append the file's mtime so browsers cannot serve a stale copy after a
    # deploy. nginx sets `expires 1d` on /css/ and /js/, so without this a
    # returning visitor can run new HTML against yesterday's stylesheet.
    def asset_path(path)
      full = File.join(settings.public_folder, path)
      stamp = File.exist?(full) ? File.mtime(full).to_i : nil
      stamp ? "#{path}?v=#{stamp}" : path
    end

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

  # Production answers only for its own hostnames. CHIP_ATLAS_PERMITTED_HOSTS
  # (comma-separated, e.g. ".chip-atlas.org,203.0.113.10") widens that for a
  # test instance reached by IP without editing the code; a leading dot
  # matches the domain and its subdomains, as Sinatra's host_authorization
  # documents.
  DEFAULT_PERMITTED_HOSTS = ['.chip-atlas.org'].freeze

  # Comma-separated env value -> list of hosts; blank/unset -> the default.
  def self.permitted_hosts_from(value)
    hosts = value.to_s.split(',').map(&:strip).reject(&:empty?)
    hosts.empty? ? DEFAULT_PERMITTED_HOSTS : hosts
  end

  configure :production do
    set :host_authorization, { permitted_hosts: permitted_hosts_from(ENV['CHIP_ATLAS_PERMITTED_HOSTS']) }
  end
end
