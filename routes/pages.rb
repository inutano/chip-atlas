# frozen_string_literal: true

module ChipAtlas
  module Routes
    module Pages
      def self.registered(app)
        app.helpers do
          def load_analysis_settings
            @index_all_genome = ChipAtlas::Experiment.cached_index_all_genome
            @list_of_genome   = ChipAtlas::Experiment.list_of_genome
            @qval_range       = ChipAtlas::Bedfile.qval_range
          end
        end

        app.get '/' do
          @number_of_experiments = ChipAtlas::Experiment.formatted_experiment_count
          @page_js = 'homepage'
          erb :about
        end

        app.get '/peak_browser' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'peak-browser'
          erb :peak_browser
        end

        app.get '/view' do
          halt 400, json_response({ error: 'id parameter required' }) unless params[:id]
          @expid = params[:id].upcase
          if @expid.start_with?('GSM')
            srx = ChipAtlas::ExperimentSearch.gsm_to_srx(@expid)
            redirect "/view?id=#{srx}" if srx
          end
          redirect '/not_found', 404 unless ChipAtlas::Experiment.id_valid?(@expid)
          log_activity('view_experiment', { expid: @expid })
          @records = ChipAtlas::Experiment.record_by_experiment_id(@expid)
          @ncbi = ChipAtlas::SraService.new(@expid).fetch
          @page_js = 'experiment'
          erb :experiment
        end

        app.get '/colo' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'colo'
          erb :colo
        end

        app.get '/colo_result' do
          @page_js = 'colo-result'
          erb :colo_result
        end

        app.get '/target_genes' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'target-genes'
          erb :target_genes
        end

        app.get '/target_genes_result' do
          @page_js = 'target-genes-result'
          erb :target_genes_result
        end

        app.get '/enrichment_analysis' do
          load_analysis_settings
          erb :enrichment_analysis
        end

        app.post '/enrichment_analysis' do
          @taxonomy  = params['taxonomy']
          @genes     = params['genes']
          @genesetA  = params['genesetA']
          @genesetB  = params['genesetB']
          log_activity('enrichment_analysis', { taxonomy: @taxonomy })
          load_analysis_settings
          erb :enrichment_analysis
        end

        app.get '/enrichment_analysis_result' do
          @page_js = 'enrichment-result'
          erb :enrichment_analysis_result
        end

        app.get '/diff_analysis' do
          load_analysis_settings
          erb :diff_analysis
        end

        app.get '/diff_analysis_result' do
          @page_js = 'diff-result'
          erb :diff_analysis_result
        end

        app.get '/search' do
          @page_js = 'search'
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
