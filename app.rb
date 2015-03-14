# :)

require 'sinatra'
require 'haml'
require 'sass'

class PeakJohn < Sinatra::Base
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
