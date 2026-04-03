# frozen_string_literal: true
# :)

require 'bundler/setup'
require 'json'
require 'net/http'
require 'uri'
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

  def self.format_number(n)
    n.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')
  end
  private_class_method :format_number

  configure do
    set :wabi_endpoint, 'https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/'

    unless ENV['SKIP_APP_CONFIGURE']
      count = ChipAtlas::Experiment.number_of_experiments
      set :number_of_experiments, format_number((count / 1000) * 1000)
      set :index_all_genome, ChipAtlas::Experiment.index_all_genome
      set :list_of_genome, ChipAtlas::Experiment.list_of_genome
      set :list_of_experiment_types, ChipAtlas::Experiment.list_of_experiment_types
      set :qval_range, ChipAtlas::Bedfile.qval_range
      set :target_genes_analysis, ChipAtlas::Analysis.target_genes_result
      set :bedsizes, ChipAtlas::Bedsize.dump
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
