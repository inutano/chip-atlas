# frozen_string_literal: true

module ChipAtlas
  module Routes
    module Pages
      def self.registered(app)
        app.helpers do
          def check_remote_result(url)
            halt 404 unless url&.start_with?('https://chip-atlas.dbcls.jp/')
            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.open_timeout = 5
            http.read_timeout = 10
            response = http.request_head(uri.path)
            response.code == '200' ? redirect(url) : (halt 404)
          rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError
            halt 404
          end
        end

        app.get '/' do
          @number_of_experiments = settings.respond_to?(:number_of_experiments) ? settings.number_of_experiments : '0'
          erb :about
        end

        app.get '/peak_browser' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :peak_browser
        end

        app.get '/view' do
          @expid = params[:id].upcase
          if @expid.start_with?('GSM')
            srx = ChipAtlas::ExperimentSearch.gsm_to_srx(@expid)
            redirect "/view?id=#{srx}" if srx
          end
          redirect '/not_found', 404 unless ChipAtlas::Experiment.id_valid?(@expid)
          @ncbi = ChipAtlas::SraService.new(@expid).fetch
          erb :experiment
        end

        app.get '/colo' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome = settings.list_of_genome
          erb :colo
        end

        app.get '/colo_result' do
          check_remote_result(params[:base])
        end

        app.get '/target_genes' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome = settings.list_of_genome
          erb :target_genes
        end

        app.get '/target_genes_result' do
          check_remote_result(params[:base])
        end

        app.get '/enrichment_analysis' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :enrichment_analysis
        end

        app.post '/enrichment_analysis' do
          @taxonomy  = params['taxonomy']
          @genes     = params['genes']
          @genesetA  = params['genesetA']
          @genesetB  = params['genesetB']
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :enrichment_analysis
        end

        app.get '/enrichment_analysis_result' do
          erb :enrichment_analysis_result
        end

        app.get '/diff_analysis' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :diff_analysis
        end

        app.get '/diff_analysis_result' do
          erb :diff_analysis_result
        end

        app.get '/search' do
          erb :search
        end

        app.get '/publications' do
          erb :publications
        end

        app.get '/agents' do
          erb :agents
        end

        app.get '/demo' do
          erb :demo
        end

        app.not_found do
          begin
            erb :not_found
          rescue Errno::ENOENT
            'Not Found'
          end
        end
      end
    end
  end
end
