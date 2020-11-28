# :)

# add current directory and lib directory to load path
$LOAD_PATH << __dir__
$LOAD_PATH << File.join(__dir__, "lib")

require 'sinatra'
require 'sinatra/activerecord'
require 'haml'
require 'sass'
require 'open-uri'
require 'net/http'
require 'uri'
require 'json'
require 'nokogiri'
require 'lib/pj'
require 'fileutils'
require 'redcarpet'

ENV["DATABASE_URL"] ||= "sqlite3:database.sqlite"

class PeakJohn < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  set :database, ENV["DATABASE_URL"]

  helpers do
    def app_root
      "#{env["rack.url_scheme"]}://#{env["HTTP_HOST"]}#{env["SCRIPT_NAME"]}"
    end
  end

  configure do
    begin
      set :number_of_experiments, ((PJ::Experiment.all.size / 1000) * 1000).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      set :index_all_genome, PJ::Experiment.index_all_genome
      set :list_of_genome, PJ::Experiment.list_of_genome
      set :qval_range, PJ::Bedfile.qval_range
      set :colo_analysis, PJ::Analysis.results(:colo)
      set :target_genes_analysis, PJ::Analysis.results(:target_genes)
      set :bedsizes, PJ::Bedsize.dump
    rescue ActiveRecord::StatementInvalid
      # Ignore Statement Invalid error when the database is not yet prepared
    end
  end

  before do
    rack_input = request.env["rack.input"].read
    if !rack_input.empty?
      posted_data = JSON.parse(rack_input) rescue nil
      if posted_data
        log = [Time.now, request.ip, request.path_info, posted_data].join("\t")
        logfile = "./log/access_log"
        logdir = File.dirname(logfile)
        FileUtils.mkdir(logdir) if !File.exist?(logdir)
        open(logfile,"a"){|f| f.puts(log) }
      end
    end
  end

  get "/:source.css" do
    sass params[:source].intern
  end

  get "/data/:data.json" do
    data = case params[:data]
           when "index_all_genome"
             settings.index_all_genome
           when "list_of_genome"
             settings.list_of_genome
           when "qval_range"
             settings.qval_range
           when "exp_metadata"
             PJ::Experiment.record_by_expid(params[:expid])
           when "colo_analysis"
             # settings.colo_analysis
             PJ::Analysis.colo_result_by_genome(params[:genome])
           when "target_genes_analysis"
             settings.target_genes_analysis
           when "number_of_lines"
             settings.bedsizes
           when "fastqc_images"
             PJ::FastQC.get_images_url(params[:expid], app_root)
           when "fastqc_dir" # seems not to be used anywhere
             PJ::FastQC.new(params[:runid], app_root).read_quality_dir
           when "index_subclass"
             genome        = params[:genome]
             ag_class      = params[:agClass]
             cl_class      = params[:clClass]
             subclass_type = params[:type]
             PJ::Experiment.get_subclass(genome, ag_class, cl_class, subclass_type)
           end
    content_type "application/json"
    JSON.dump(data)
  end

  get "/" do
    @number_of_experiments = settings.number_of_experiments
    haml :about
  end

  get "/peak_browser" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome   = settings.list_of_genome
    @qval_range       = settings.qval_range
    haml :peak_browser
  end

  get "/colo" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = settings.list_of_genome
    haml :colo
  end

  get "/target_genes" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = settings.list_of_genome
    haml :target_genes
  end

  get "/enrichment_analysis" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = settings.list_of_genome
    @qval_range = settings.qval_range
    haml :enrichment_analysis
  end

  post "/enrichment_analysis" do
    request.body.rewind
    params_raw = request.body.read
    params_arr = params_raw.split("&").map{|k_v| k_v.split("=") }
    params = Hash[params_arr]

    @taxonomy = params["taxonomy"]
    @genes = params["genes"]
    @genesetA = params["genesetA"]
    @genesetB = params["genesetB"]

    @index_all_genome = settings.index_all_genome
    @list_of_genome = @index_all_genome.keys
    @qval_range = settings.qval_range

    haml :enrichment_analysis
  end

  get "/enrichment_analysis_result" do
    haml :enrichment_analysis_result
  end

  post "/colo" do
    request.body.rewind
    json = request.body.read
    content_type "application/json"
    colo_url = PJ::Location.new(JSON.parse(json)).colo_url(params[:type])
    JSON.dump({ "url" => colo_url })
  end

  get "/colo_result" do
    @iframe_url = params[:base]
    # haml :colo_result
    if remotefile_available?(@iframe_url)
      redirect @iframe_url
    else
      redirect "not_found", 404
    end
  end

  post "/target_genes" do
    request.body.rewind
    json = request.body.read
    content_type "application/json"
    target_genes_url = PJ::Location.new(JSON.parse(json)).target_genes_url(params[:type])
    JSON.dump({ "url" => target_genes_url })
  end

  get "/target_genes_result" do
    @iframe_url = params[:base]
    # haml :target_genes_result
    if remotefile_available?(@iframe_url)
      redirect @iframe_url
    else
      redirect "not_found", 404
    end
  end

  post "/browse" do
    request.body.rewind
    json = request.body.read
    content_type "application/json"
    url = PJ::Location.new(JSON.parse(json)).igv_browsing_url
    JSON.dump({ "url" => url })
  end

  post "/download" do
    request.body.rewind
    json = request.body.read
    content_type "application/json"
    url = PJ::Location.new(JSON.parse(json)).archived_bed_url
    JSON.dump({ "url" => url })
  end

  get "/wabi_chipatlas" do
    url = "http://ddbj.nig.ac.jp/wabi/chipatlas/" + params[:id] + "?info=result&format=html"
    if Net::HTTP.get_response(URI.parse(url)).code == "200"
      if !open(url).read.empty?
        "finished"
      else
        "running"
      end
    else
      "queued"
    end
  end

  post "/wabi_chipatlas" do
    request.body.rewind
    wabi_response = Net::HTTP.post_form(URI.parse('http://ddbj.nig.ac.jp/wabi/chipatlas/'), JSON.parse(request.body.read))
    wabi_response_body = wabi_response.body
    if wabi_response_body
      id = wabi_response_body.split("\n").select{|n| n =~ /^requestId/ }.first.split("\s").last
      JSON.dump({ "requestId" => id })
    else
      JSON.dump({ "request_body" => wabi_request_body })
    end
  end

  get "/view" do
    @expid = params[:id]
    redirect "not_found", 404 if !PJ::Experiment.id_valid?(@expid)
    @ncbi  = PJ::SRA.new(@expid).fetch
    haml :experiment
  end

  get "/api/remoteUrlStatus" do
    Net::HTTP.get_response(URI.parse(params[:url])).code.to_i
  end

  get "/publications" do
    haml :publications
  end

  not_found do
    haml :not_found
  end
end
