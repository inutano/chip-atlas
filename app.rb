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
    
    def igv_browsing_url(data)
      igv_url   = data["igv"] || "http://localhost:60151"
      condition = data["condition"]
      genome    = condition["genome"]
      filename  = Bedfile.get_filename(condition)
    
      archive_path = File.join(archive_base, genome, "assembled", filename + ".bed")
      "#{igv_url}/load?genome=#{genome}&file=#{archive_path}"
    end
  end
  
  get "/:source.css" do
    sass params[:source].intern
  end
  
  get "/" do
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
    open(fpath).read.split("\n").each do |line|
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

  get "/colo_result" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    
    h = {}
    fpath = File.join(app_root, "analysisList.tab")
    open(fpath).read.split("\n").each do |line|
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
    
    haml :colo_test
  end
  

  get "/target_gene" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    
    h = {}
    fpath = File.join(app_root, "analysisList.tab")
    open(fpath).read.split("\n").each do |line|
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
    
    haml :target_gene
  end
  
  get "/target_gene_result" do
    @index_all_genome = Experiment.index_all_genome
    @list_of_genome = @index_all_genome.keys
    
    h = {}
    fpath = File.join(app_root, "analysisList.tab")
    open(fpath).read.split("\n").each do |line|
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
    
    haml :target_gene_test
  end
  
  post "/browse" do
    content_type "application/json"
    JSON.dump({ "url" => igv_browsing_url(JSON.parse(request.body.read)) })
  end
  
  get "/view" do
    @expid = params[:id]
    404 if Experiment.id_valid?(@expid)
    @ncbi  = Experiment.fetch_ncbi_metadata(@expid)
    puts @ncbi
    haml :experiment
  end
end
