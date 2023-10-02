# :)

# add current directory and lib directory to load path
$LOAD_PATH << __dir__
$LOAD_PATH << File.join(__dir__, "lib")

require 'sinatra'
require 'sinatra/activerecord'
require 'haml'
require 'sass'
require 'open-uri'
require 'timeout'
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

    def wabi_endpoint_status
      Timeout.timeout(3) do
        open(settings.wabi_endpoint).read
      end
    rescue OpenURI::HTTPError
      nil
    rescue Timeout::Error
      nil
    end
  end

  configure do
    begin
      set :number_of_experiments, ((PJ::Experiment.number_of_experiments / 1000) * 1000).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      set :index_all_genome, PJ::Experiment.index_all_genome
      set :list_of_genome, PJ::Experiment.list_of_genome
      set :list_of_experiment_types, PJ::Experiment.list_of_experiment_types
      set :qval_range, PJ::Bedfile.qval_range
      set :colo_analysis, PJ::Analysis.results(:colo)
      set :target_genes_analysis, PJ::Analysis.results(:target_genes)
      set :bedsizes, PJ::Bedsize.dump
      set :experiment_list, JSON.load(open("https://chip-atlas.dbcls.jp/data/metadata/ExperimentList.json"))
      set :experiment_list_adv, JSON.load(open("https://chip-atlas.dbcls.jp/data/metadata/ExperimentList_adv.json"))
      set :gsm_to_srx, Hash[settings.experiment_list["data"].map{|a| [a[2], a[0]] }]
      set :wabi_endpoint, "https://ddbj.nig.ac.jp/wabi/chipatlas/"
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

  after do
    ActiveRecord::Base.clear_active_connections!
  end

  get "/:source.css" do
    sass params[:source].intern
  end

  get "/data/:data.json" do
    data = case params[:data]
           when "index_all_genome"
             settings.index_all_genome
           when "list_of_genome"
             settings.list_of_genome.keys
           when "list_of_experiment_types"
             settings.list_of_experiment_types
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
           when "ExperimentList"
             settings.experiment_list
           when "ExperimentList_adv"
             settings.experiment_list_adv
           end
    content_type "application/json"
    JSON.dump(data)
  end

  get '/data/experiment_types' do
    genome   = params[:genome]
    cl_class = params[:clClass]
    data = PJ::Experiment.experiment_types(genome, cl_class)

    content_type "application/json"
    JSON(data)
  end

  get '/data/sample_types' do
    genome   = params[:genome]
    ag_class = params[:agClass]
    data = PJ::Experiment.sample_types(genome, ag_class)

    content_type "application/json"
    JSON(data)
  end

  get '/data/chip_antigen' do
    genome   = params[:genome]
    ag_class = params[:agClass]
    cl_class = params[:clClass]
    data = PJ::Experiment.chip_antigen(genome, ag_class, cl_class)

    content_type "application/json"
    JSON(data)
  end

  get '/data/cell_type' do
    genome   = params[:genome]
    ag_class = params[:agClass]
    cl_class = params[:clClass]
    data = PJ::Experiment.cell_type(genome, ag_class, cl_class)

    content_type "application/json"
    JSON(data)
  end

  get "/" do
    @number_of_experiments = settings.number_of_experiments
    haml :about
  end

  get "/qvalue_range" do
    content_type "application/json"
    JSON(settings.qval_range)
  end

  #
  # Peak Browser
  #

  get "/peak_browser" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome   = settings.list_of_genome
    @qval_range       = settings.qval_range
    haml :peak_browser
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
    puts "DOWNLOAD: JSON: #{JSON.parse(json)}, URL: #{url}"
    JSON.dump({ "url" => url })
  end

  get "/view" do
    @expid = params[:id]
    if @expid =~ /^GSM/
      redirect "/view?id=#{settings.gsm_to_srx[@expid]}"
    end
    redirect "not_found", 404 if !PJ::Experiment.id_valid?(@expid)
    @ncbi  = PJ::SRA.new(@expid).fetch
    haml :experiment
  end

  #
  # Colocalization analysis
  #

  get "/colo" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = settings.list_of_genome
    haml :colo
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

  #
  # Target genes analysis
  #

  get "/target_genes" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = settings.list_of_genome
    haml :target_genes
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

  #
  # Enrichment analysis
  #

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
    @list_of_genome = settings.list_of_genome
    @qval_range = settings.qval_range

    haml :enrichment_analysis
  end

  get "/enrichment_analysis_result" do
    haml :enrichment_analysis_result
  end

  #
  # Diff Analysis
  #

  get "/diff_analysis" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = settings.list_of_genome
    @qval_range = settings.qval_range
    haml :diff_analysis
  end

  get "/diff_analysis_result" do
    haml :diff_analysis_result
  end

  #
  # Experiment search
  #

  get "/search" do
    haml :search
  end

  #
  # Publication page
  #

  get "/publications" do
    haml :publications
  end

  #
  # 404 Not Found
  #

  not_found do
    haml :not_found
  end

  #
  # DDBJ Supercomputer system WABI API
  #

  get "/wabi_chipatlas" do
    url = "http://ddbj.nig.ac.jp/wabi/chipatlas/" + params[:id] + "?format=json"
    if Net::HTTP.get_response(URI.parse(url)).code == "200"
      JSON.load(open(url).read)["status"]
    else
      "Error"
    end
  end

  get "/wabi_endpoint_status" do
    wabi_endpoint_status
  end

  post "/wabi_chipatlas" do
    request.body.rewind
    request_body = request.body.read

    if wabi_endpoint_status != 'chipatlas'
      status 503
    else
      wabi_response = Net::HTTP.post_form(URI.parse(settings.wabi_endpoint), JSON.parse(request_body))
      wabi_response_body = wabi_response.body
      if wabi_response_body
        id = wabi_response_body.split("\n").select{|n| n =~ /^requestId/ }.first.split("\s").last
        JSON.dump({ "requestId" => id })
      else
        JSON.dump({ "request_body" => wabi_request_body })
      end
    end
  rescue => e
    puts "ERROR: #{e}, BODY: #{wabi_response_body}"
    redirect "not_found", 404
  end

  get "/api/remoteUrlStatus" do
    Net::HTTP.get_response(URI.parse(params[:url])).code.to_i
  end
end
