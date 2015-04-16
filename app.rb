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
    
    def archive_base
      "http://dbarchive.biosciencedbc.jp/kyushu-u/hg19/assembled/"
    end
  end
  
  get "/:source.css" do
    sass params[:source].intern
  end
  
  get "/" do
    haml :index
  end
  
  get "/index" do
    genome = params[:genome]
    404 if !Bedfile.list_of_genome.include?(genome)
    JSON.dump(Bedfile.index_by_genome(genome))
  end
  
  post "/browse" do
    data = JSON.parse(request.body.read)
    igv_url = data["igv"] || "localhost:60151"
    archive_path = Bedfile.archive_path(archive_base, data["condition"])
    redirect_to = "http://#{igv_url}/load?genome=#{data["condition"]["genome"]}&file=#{archive_path}"
    JSON.dump({ "url" => redirect_to })
  end
end
