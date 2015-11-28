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

    def get_fastqc_image(run_id) ## :( ##
      head = run_id.sub(/...$/,"")
      path = File.join("http://data.dbcls.jp/~inutano/fastqc", head, run_id)
      save_path = "./public/images/fastqc/#{head}/#{run_id}"

      files = ["_fastqc","_1_fastqc","_2_fastqc"].map do |read|
        File.join(app_root, "images/fastqc/#{head}/#{run_id}", run_id+read, "Images/per_base_quality.png")
      end

      fstatus = files.map do |url|
        uri = URI(url)
        request = Net::HTTP.new(uri.host, uri.port)
        response = request.request_head(uri.path)
        response.code.to_i
      end

      if !fstatus.include?(200)
        FileUtils.mkdir_p(save_path) if !File.exist?(save_path)
        Net::HTTP.start("data.dbcls.jp") do |http|
          ["_fastqc.zip","_1_fastqc.zip","_2_fastqc.zip"].each do |suffix|
            fname = run_id + suffix
            resp = http.get("/~inutano/fastqc/#{head}/#{run_id}/#{fname}")
            open(File.join(save_path,fname), "wb") do |file|
              file.write(resp.body)
            end
          end
        end
        `unzip -d "#{save_path}" "#{save_path}/*zip"`
      end

      return files.select do |url|
        uri = URI(url)
        request = Net::HTTP.new(uri.host, uri.port)
        response = request.request_head(uri.path)
        response.code.to_i == 200
      end
    end

    def remotefile_available?(url)
      uri = URI(url)
      request = Net::HTTP.new(uri.host, uri.port)
      response = request.request_head(uri.path)
      response.code.to_i == 200
    end

    def exp2run(exp_id)
      h = open(File.join(app_root, "tables/exp2run.json")){|f| JSON.load(f) }
      h[exp_id]
    end

    def get_images_path(exp_id)
      exp2run(exp_id).map{|id| get_fastqc_image(id) }.flatten
    end

    def number_of_lines
      data = open("http://dbarchive.biosciencedbc.jp/kyushu-u/util/lineNum.tsv").read
      h = {}
      data.split("\n").each do |line|
        l = line.split("\t")
        h[l[0..3].join(",")] = l[4]
      end
      h
    end
  end

  configure do
    #set :index_all_genome, PJ::Experiment.index_all_genome
    #set :list_of_genome, PJ::Experiment.list_of_genome
    #set :qval_range, PJ::Bedfile.qval_range
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
             PJ::Analysis.results(:colo)
           when "target_genes_analysis"
             PJ::Analysis.results(:target_genes)
           when "number_of_lines"
             number_of_lines
           end
    content_type "application/json"
    JSON.dump(data)
  end

  get "/index" do
    genome        = params[:genome]
    ag_class      = params[:agClass]
    cl_class      = params[:clClass]
    subclass_type = params[:type]
    result = PJ::Experiment.get_subclass(genome, ag_class, cl_class, subclass_type)
    content_type "application/json"
    JSON.dump(result)
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
    target_genes_url = PJ::Loacation.new(JSON.parse(json)).target_genes_url(params[:type])
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
    JSON.dump({ "url" => PJ.igv_browsing_url(JSON.parse(json)) })
  end

  post "/download" do
    request.body.rewind
    json = request.body.read
    content_type "application/json"
    JSON.dump({ "url" => PJ::Bedfile.archive_url(JSON.parse(json)) })
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
    @ncbi  = PJ::Experiment.fetch_ncbi_metadata(@expid)
    haml :experiment
  end

  not_found do
    haml :not_found
  end
end
