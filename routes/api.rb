require 'net/http'

module ChipAtlas
  module Routes
    module Api
      ALLOWED_HOSTS = %w[
        chip-atlas.dbcls.jp
        dtn1.ddbj.nig.ac.jp
      ].freeze

      def self.allowed_remote_url?(url)
        uri = URI.parse(url)
        return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        ALLOWED_HOSTS.any? { |host| uri.host&.end_with?(host) }
      rescue URI::InvalidURIError
        false
      end

      def self.registered(app)
        app.get '/data/:data.json' do
          data = case params[:data]
                 when 'index_all_genome'          then settings.index_all_genome
                 when 'list_of_genome'            then settings.list_of_genome.keys
                 when 'list_of_experiment_types'  then settings.list_of_experiment_types
                 when 'qval_range'                then settings.qval_range
                 when 'exp_metadata'              then ChipAtlas::Experiment.record_by_exp_id(params[:expid])
                 when 'colo_analysis'             then ChipAtlas::Analysis.colo_result_by_genome(params[:genome])
                 when 'target_genes_analysis'     then settings.target_genes_analysis
                 when 'number_of_lines'           then settings.bedsizes
                 when 'index_subclass'
                   ChipAtlas::Experiment.get_subclass(
                     params[:genome], params[:agClass], params[:clClass], params[:type]
                   )
                 when 'ExperimentList'            then settings.experiment_list
                 when 'ExperimentList_adv'        then settings.experiment_list_adv
                 end
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/experiment_types' do
          data = ChipAtlas::Experiment.experiment_types(params[:genome], params[:clClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/sample_types' do
          data = ChipAtlas::Experiment.sample_types(params[:genome], params[:agClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/chip_antigen' do
          data = ChipAtlas::Experiment.chip_antigen(params[:genome], params[:agClass], params[:clClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/cell_type' do
          data = ChipAtlas::Experiment.cell_type(params[:genome], params[:agClass], params[:clClass])
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/data/search' do
          query  = params[:q]
          genome = params[:genome]
          limit  = (params[:limit] || 20).to_i.clamp(1, 100)
          offset = (params[:offset] || 0).to_i
          data = ChipAtlas::ExperimentSearch.search(query, genome: genome, limit: limit, offset: offset)
          content_type 'application/json'
          JSON.generate(data)
        end

        app.get '/qvalue_range' do
          content_type 'application/json'
          JSON.generate(settings.qval_range)
        end

        app.post '/browse' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).igv_browsing_url
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/download' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).archive_url
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/colo' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).colo_url(params[:type])
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/target_genes' do
          request.body.rewind
          json = JSON.parse(request.body.read)
          url = ChipAtlas::LocationService.new(json).target_genes_url(params[:type])
          content_type 'application/json'
          JSON.generate({ 'url' => url })
        end

        app.post '/diff_analysis_estimated_time' do
          request.body.rewind
          data = JSON.parse(request.body.read)
          total_reads = ChipAtlas::Experiment.total_number_of_reads(data['ids']).to_i
          seconds = case data['analysis']
                    when 'dmr'      then 117.13 * Math.log(total_reads) - 2012.5 + 600
                    when 'diffbind' then 1.80e-6 * total_reads + 119.38 + 600
                    end
          minutes = (seconds && !seconds.infinite?) ? Rational(seconds, 60).to_f.round : nil
          content_type 'application/json'
          JSON.generate({ minutes: minutes })
        end

        app.get '/api/remoteUrlStatus' do
          url = params[:url]
          unless url && ChipAtlas::Routes::Api.allowed_remote_url?(url)
            halt 400, 'Invalid or disallowed URL'
          end
          begin
            Net::HTTP.get_response(URI.parse(url)).code.to_i.to_s
          rescue => e
            '500'
          end
        end
      end
    end
  end
end
