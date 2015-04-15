# :)

require 'sinatra'
require 'sinatra/activerecord'
require 'haml'
require 'sass'
require 'open-uri'
require './lib/peakjohn'

ENV["DATABASE_URL"] ||= "sqlite3:database.sqlite"

class PeakJohn < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  set :database, ENV["DATABASE_URL"]

  helpers do
    def app_root
      "#{env["rack.url_scheme"]}://#{env["HTTP_HOST"]}#{env["SCRIPT_NAME"]}"
    end
  end
  
  get "/:source.css" do
    sass params[:source].intern
  end

  get "/" do
    @list = open("#{app_root}/filelist.tab").readlines.map do |line_n|
      line_n.chomp.split("\t")
    end
    haml :index
  end
  
  post "/view" do
    data = JSON.parse(request.body.read)
    ag_class = data["agClass"]
    ag_subclass = data["agSubClass"]
    cl_class = data["clClass"]
    cl_subclass = data["clSubClass"]
    qval = data["qval"]
    filename = open("#{app_root}/filelist.tab").readlines.select do |line_n|
      line = line_n.chomp.split("\t")
      line[1] == ag_class && \
      line[2] == cl_class && \
      line[3] == qval && \
      line[4] == ag_subclass && \
      line[5] == cl_subclass
    end
    fname = filename.first.split("\t").first.sub("bed","bb")
    JSON.dump({ "url" => "http://localhost:60151/load?file=http://dbarchive.biosciencedbc.jp/kyushu-u/hg19/assembled/#{fname}&genome=hg19"})
  end
end
