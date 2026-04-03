# frozen_string_literal: true
# :)

require 'bundler/setup'
require 'json'
require 'net/http'
require 'uri'
require 'open-uri'
require 'timeout'
require 'fileutils'
require 'sinatra/base'

require_relative 'lib/db'

require_relative 'lib/chip_atlas'
require_relative 'routes/health'
require_relative 'routes/api'
require_relative 'routes/pages'
require_relative 'routes/wabi'

class ChipAtlasApp < Sinatra::Base
  set :erb, escape_html: true
  set :views, File.join(File.dirname(__FILE__), 'views')

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
  end

  def self.download_json_with_fallback(remote_url, local_filename)
    local_path = File.join('public', local_filename)

    if File.exist?(local_path)
      warn "Using cached file: #{local_path}"
      return JSON.parse(File.read(local_path))
    end

    begin
      warn "No cached file found, downloading from remote: #{remote_url}"
      Timeout.timeout(30) do
        content = URI.open(remote_url).read
        File.write(local_path, content)
        JSON.parse(content)
      end
    rescue => e
      warn "Failed to download #{remote_url}: #{e.message}"
      raise "Unable to load #{remote_url} and no cached file available"
    end
  end
  private_class_method :download_json_with_fallback

  configure do
    set :wabi_endpoint, 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/'

    unless ENV['SKIP_APP_CONFIGURE']
      count = ChipAtlas::Experiment.number_of_experiments
      set :number_of_experiments, (count / 1000 * 1000).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      set :index_all_genome, ChipAtlas::Experiment.index_all_genome
      set :list_of_genome, ChipAtlas::Experiment.list_of_genome
      set :list_of_experiment_types, ChipAtlas::Experiment.list_of_experiment_types
      set :qval_range, ChipAtlas::Bedfile.qval_range
      set :target_genes_analysis, ChipAtlas::Analysis.target_genes_result
      set :bedsizes, ChipAtlas::Bedsize.dump

      set :experiment_list, download_json_with_fallback(
        'https://chip-atlas.dbcls.jp/data/metadata/ExperimentList.json', 'ExperimentList.json'
      )
      set :experiment_list_adv, download_json_with_fallback(
        'https://chip-atlas.dbcls.jp/data/metadata/ExperimentList_adv.json', 'ExperimentList_adv.json'
      )
      ChipAtlas::ExperimentSearch.load_from_json(settings.experiment_list_adv)
      set :gsm_to_srx, settings.experiment_list['data'].to_h { |a| [a[2], a[0]] }
    end
  end

  configure :production do
    set :host_authorization, { permitted_hosts: ['.chip-atlas.org'] }
  end

  before do
    if request.post?
      rack_input = request.env['rack.input']&.read.to_s
      unless rack_input.empty?
        begin
          posted_data = JSON.parse(rack_input)
        rescue JSON::ParserError
          posted_data = nil
        end
        if posted_data
          log = [Time.now, request.ip, request.path_info, posted_data].join("\t")
          logfile = './log/access_log'
          FileUtils.mkdir_p(File.dirname(logfile))
          File.open(logfile, 'a') { |f| f.puts(log) }
        end
      end
    end
  end
end
