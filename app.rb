# :)

require 'sinatra'
require 'sinatra/activerecord'
require 'haml'
require 'sass'
require 'open-uri'
require 'net/http'
require 'json'
require 'nokogiri'
require './lib/peakjohn'

ENV["DATABASE_URL"] ||= "sqlite3:database.sqlite"

class PeakJohn < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  set :database, ENV["DATABASE_URL"]

  helpers do
    def app_root
      "#{env["rack.url_scheme"]}://#{env["HTTP_HOST"]}#{env["SCRIPT_NAME"]}"
    end
    
    def archive_base
      "http://dbarchive.biosciencedbc.jp/kyushu-u/"
    end
    
    def fileformat
      # ".bed"
      ".bb"
    end
    
    def bedfile_archive(data)
      condition = data["condition"]
      genome    = condition["genome"]
      filename = Bedfile.get_filename(condition)
      File.join(archive_base, genome, "assembled", filename + fileformat)
    rescue NameError
      nil
    end
    
    def igv_browsing_url(data)
      igv_url   = data["igv"] || "http://localhost:60151"
      condition = data["condition"]
      genome    = condition["genome"]
      "#{igv_url}/load?genome=#{genome}&file=#{bedfile_archive(data)}"
    end

    def colo_url(data)
      base = "http://devbio.med.kyushu-u.ac.jp/chipome/colo"
      condition = data["condition"]
      genome    = condition["genome"]
      antigen   = condition["antigen"]
      cellline  = condition["cellline"].gsub("\s","_")
      "#{app_root}/colo_result?base=#{base}/#{antigen}.#{cellline}.html"
    end

    def target_genes_url(data)
      base = "http://devbio.med.kyushu-u.ac.jp/chipome/targetGenes"
      condition = data["condition"]
      genome    = condition["genome"]
      antigen   = condition["antigen"]
      "#{app_root}/target_genes_result?base=#{base}/#{antigen}.html"
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
    
    def exp2run(exp_id)
      h = open(File.join(app_root, "tables/exp2run.json")){|f| JSON.load(f) }
      h[exp_id]
    end
    
    def get_images_path(exp_id)
      exp2run(exp_id).map{|id| get_fastqc_image(id) }.flatten
    end
    
    def number_of_lines
      data = open("http://dbarchive.biosciencedbc.jp/kyushu-u/lib/lineNum.tsv").read
      h = {}
      data.split("\n").each do |line|
        l = line.split("\t")
        h[l[0..3].join(",")] = l[4]
      end
      h
    end
  end
  
  get "/:source.css" do
    sass params[:source].intern
  end
  
  get "/" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    @qval_range = Bedfile.qval_range
    haml :about
  end
  
  get "/peak_browser" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    @qval_range = Bedfile.qval_range
    haml :peak_browser
  end
  
  get "/colo" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    
    h = {}
    fpath = File.join(app_root, "analysisList.tab")
    open(fpath, "r:UTF-8").read.split("\n").each do |line|
      cols = line.split("\t")
      antigen = cols[0]
      cell_list = cols[1].split(",")
      genome = cols[3]
      
      h[genome] ||= {}
      h[genome][:antigen] ||= {}
      h[genome][:antigen][antigen] = cell_list
      
      cell_list.each do |cl|
        h[genome][:cellline] ||= {}
        h[genome][:cellline][cl] ||= []
        h[genome][:cellline][cl] << antigen
      end
    end
    @analysis = h
    
    haml :colo
  end

  get "/target_genes" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    
    h = {}
    fpath = File.join(app_root, "analysisList.tab")
    open(fpath, "r:UTF-8").read.split("\n").each do |line|
      cols = line.split("\t")
      antigen = cols[0]
      status = cols[2]
      genome = cols[3]
      if status == "+"
        h[genome] ||= []
        h[genome] << antigen
      end
    end
    @analysis = h
    
    haml :target_genes
  end
  
  get "/in_silico_chip" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    @qval_range = Bedfile.qval_range
    @number_of_lines = number_of_lines
    haml :in_silico_chip
  end
  
  post "/colo" do
    content_type "application/json"
    JSON.dump({ "url" => colo_url(JSON.parse(request.body.read)) })
  end

  get "/colo_result" do
    @iframe_url = params[:base]
    haml :colo_result
  end
  
  post "/target_genes" do
    content_type "application/json"
    JSON.dump({ "url" => target_genes_url(JSON.parse(request.body.read)) })
  end

  get "/target_genes_result" do
    @iframe_url = params[:base]
    haml :target_genes_result
  end

  get "/documentation" do
    haml :documentation
  end
  
  post "/browse" do
    content_type "application/json"
    JSON.dump({ "url" => igv_browsing_url(JSON.parse(request.body.read)) })
  end

  post "/download" do
    fpath = bedfile_archive(JSON.parse(request.body.read))
    dest = if fpath
             fpath
           else
             '/not_found'
           end
    puts dest
    redirect dest
  end
  
  post "/wabi_chipatlas" do
    json_headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
    uri = URI.parse('http://ddbj.nig.ac.jp/wabi/chipatlas')
    http = Net::HTTP.new(uri.host, uri.port)
    JSON.dump(http.post(uri.path, request.body.read, json_headers))
  end
  
  get "/view" do
    @expid = params[:id]
    404 if Experiment.id_valid?(@expid)
    @ncbi  = Experiment.fetch_ncbi_metadata(@expid)
    haml :experiment
  end
end
