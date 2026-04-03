module ChipAtlas
  module Routes
    module Pages
      def self.registered(app)
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
          if @expid =~ /^GSM/
            srx = settings.respond_to?(:gsm_to_srx) ? settings.gsm_to_srx[@expid] : nil
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
          url = params[:base]
          begin
            response = Net::HTTP.get_response(URI.parse(url))
            response.code == '200' ? redirect(url) : (halt 404)
          rescue
            halt 404
          end
        end

        app.get '/target_genes' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome = settings.list_of_genome
          erb :target_genes
        end

        app.get '/target_genes_result' do
          url = params[:base]
          begin
            response = Net::HTTP.get_response(URI.parse(url))
            response.code == '200' ? redirect(url) : (halt 404)
          rescue
            halt 404
          end
        end

        app.get '/enrichment_analysis' do
          @index_all_genome = settings.index_all_genome
          @list_of_genome   = settings.list_of_genome
          @qval_range       = settings.qval_range
          erb :enrichment_analysis
        end

        app.post '/enrichment_analysis' do
          request.body.rewind
          raw = request.body.read
          pairs = raw.split('&').map { |kv| kv.split('=', 2) }
          form = Hash[pairs]
          @taxonomy  = form['taxonomy']
          @genes     = form['genes']
          @genesetA  = form['genesetA']
          @genesetB  = form['genesetB']
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
          erb :not_found rescue 'Not Found'
        end
      end
    end
  end
end
