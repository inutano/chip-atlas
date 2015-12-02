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
require 'json'
require 'nokogiri'
require 'lib/pj'

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
           when "fastqc_dir"
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
    haml :about
  end

  get "/peak_browser" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome   = @index_all_genome.keys
    @qval_range       = settings.qval_range
    haml :peak_browser
  end

  get "/colo" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = @index_all_genome.keys
    haml :colo
  end

  get "/target_genes" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = @index_all_genome.keys
    haml :target_genes
  end

  get "/in_silico_chip" do
    @index_all_genome = settings.index_all_genome
    @list_of_genome = @index_all_genome.keys
    @qval_range = settings.qval_range
    haml :in_silico_chip
  end

  get "/in_silico_chip_result" do
    haml :in_silico_chip_result
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
    id = params[:id]
    uge_log = open("http://ddbj.nig.ac.jp/wabi/chipatlas/"+id).read
    uge_log.split("\n").select{|l| l =~ /^status/ }[0].split(": ")[1]
  end

  post "/wabi_chipatlas" do
    # json_headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
    res = Net::HTTP.post_form(URI.parse('http://ddbj.nig.ac.jp/wabi/chipatlas/'), JSON.parse(request.body.read))
    id = res.body.split("\n").select{|n| n =~ /^requestId/ }.first.split("\s").last
    JSON.dump({ "requestId" => id })
  end

  get "/view" do
    @expid = params[:id]
    404 if PJ::Experiment.id_valid?(@expid)
    @ncbi  = PJ::SRA.new(@expid).fetch
    haml :experiment
  end

  not_found do
    haml :not_found
  end
end
