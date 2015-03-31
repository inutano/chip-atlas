# :)

require 'sinatra'
require 'sinatra/activerecord'
require 'haml'
require 'sass'
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
    haml :index
  end
end
