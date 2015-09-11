# :)

require 'sinatra'
require 'sinatra/activerecord'
require 'haml'
require 'sass'
require 'open-uri'
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
    haml :index
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
  
  get "/virtual_chip" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    @qval_range = Bedfile.qval_range
    haml :virtual_chip
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
  
  get "/view" do
    @expid = params[:id]
    404 if Experiment.id_valid?(@expid)
    @ncbi  = Experiment.fetch_ncbi_metadata(@expid)
    haml :experiment
  end
end
