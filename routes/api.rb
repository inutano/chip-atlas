# frozen_string_literal: true

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
        app.helpers do
          def condition_from_params
            {
              'condition' => {
                'genome'             => params[:genome],
                'track_class'        => params[:track_class],
                'track_subclass'     => params[:track_subclass],
                'cell_type_class'    => params[:cell_type_class],
                'cell_type_subclass' => params[:cell_type_subclass],
                'qval'               => params[:qval],
                'track'              => params[:track],
                'cell_type'          => params[:cell_type],
                'distance'           => params[:distance],
              }.compact
            }
          end
        end

        # === Classification endpoints ===

        app.get '/api/genomes' do
          cache_control :public, max_age: 86_400
          json_response(ChipAtlas::Experiment.list_of_genome.keys)
        end

        app.get '/api/track_classes' do
          if params[:genome]
            json_response(ChipAtlas::Experiment.experiment_types(params[:genome], params[:cell_type_class] || 'All cell types'))
          else
            cache_control :public, max_age: 86_400
            json_response(ChipAtlas::Experiment.list_of_experiment_types)
          end
        end

        app.get '/api/cell_type_classes' do
          halt 400, json_response({ error: 'genome and track_class required' }) unless params[:genome] && params[:track_class]
          json_response(ChipAtlas::Experiment.sample_types(params[:genome], params[:track_class]))
        end

        app.get '/api/track_subclasses' do
          halt 400, json_response({ error: 'genome and track_class required' }) unless params[:genome] && params[:track_class]
          json_response(ChipAtlas::Experiment.chip_antigen(params[:genome], params[:track_class], params[:cell_type_class]))
        end

        app.get '/api/cell_type_subclasses' do
          halt 400, json_response({ error: 'genome and track_class required' }) unless params[:genome] && params[:track_class]
          json_response(ChipAtlas::Experiment.cell_type(params[:genome], params[:track_class], params[:cell_type_class]))
        end

        app.get '/api/subclasses' do
          json_response(
            ChipAtlas::Experiment.get_subclass(
              params[:genome], params[:track_class], params[:cell_type_class], params[:type]
            )
          )
        end

        # === Data endpoints ===

        app.get '/api/genome_index' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Experiment.cached_index_all_genome)
        end

        app.get '/api/experiment' do
          halt 400, json_response({ error: 'experiment_id parameter required' }) unless params[:experiment_id]
          json_response(ChipAtlas::Experiment.record_by_experiment_id(params[:experiment_id]))
        end

        app.get '/api/search' do
          query  = params[:q]
          genome = params[:genome]
          limit  = (params[:limit] || 20).to_i.clamp(1, 100)
          offset = (params[:offset] || 0).to_i
          log_activity('search', { q: query, genome: genome })
          json_response(ChipAtlas::ExperimentSearch.search(query, genome: genome, limit: limit, offset: offset))
        end

        app.get '/api/qval_range' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Bedfile.qval_range)
        end

        app.get '/api/bed_sizes' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Bedsize.dump)
        end

        # === Analysis index endpoints ===

        app.get '/api/colo_index' do
          halt 400, json_response({ error: 'genome parameter required' }) unless params[:genome]
          json_response(ChipAtlas::Analysis.colo_result_by_genome(params[:genome]))
        end

        app.get '/api/target_genes_index' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Analysis.target_genes_result)
        end

        # === URL generation endpoints (GET for agents, POST for frontend) ===

        app.get '/api/igv_url' do
          halt 400, json_response({ error: 'genome and track_class required' }) unless params[:genome] && params[:track_class]
          url = ChipAtlas::LocationService.new(condition_from_params).igv_browsing_url
          json_response({ url: url })
        end

        app.post '/api/igv_url' do
          url = ChipAtlas::LocationService.new(parsed_json).igv_browsing_url
          json_response({ url: url })
        end

        app.get '/api/download_url' do
          halt 400, json_response({ error: 'genome and track_class required' }) unless params[:genome] && params[:track_class]
          url = ChipAtlas::LocationService.new(condition_from_params).archive_url
          json_response({ url: url })
        end

        app.post '/api/download_url' do
          url = ChipAtlas::LocationService.new(parsed_json).archive_url
          json_response({ url: url })
        end

        app.get '/api/colo_urls' do
          halt 400, json_response({ error: 'genome, track, and cell_type required' }) unless params[:genome] && params[:track] && params[:cell_type]
          svc = ChipAtlas::LocationService.new(condition_from_params)
          json_response({ data_url: svc.colo_data_url, tsv_url: svc.colo_tsv_url, gml_url: svc.colo_gml_url })
        end

        app.post '/api/colo_urls' do
          svc = ChipAtlas::LocationService.new(parsed_json)
          json_response({ data_url: svc.colo_data_url, tsv_url: svc.colo_tsv_url, gml_url: svc.colo_gml_url })
        end

        app.get '/api/target_genes_urls' do
          halt 400, json_response({ error: 'genome, track, and distance required' }) unless params[:genome] && params[:track] && params[:distance]
          svc = ChipAtlas::LocationService.new(condition_from_params)
          json_response({ data_url: svc.target_genes_data_url, tsv_url: svc.target_genes_tsv_url })
        end

        app.post '/api/target_genes_urls' do
          svc = ChipAtlas::LocationService.new(parsed_json)
          json_response({ data_url: svc.target_genes_data_url, tsv_url: svc.target_genes_tsv_url })
        end

        # === Internal endpoints (not in OpenAPI) ===

        app.get '/api/remote_url_status' do
          url = params[:url]
          unless url && ChipAtlas::Routes::Api.allowed_remote_url?(url)
            halt 400, 'Invalid or disallowed URL'
          end
          begin
            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.open_timeout = 5
            http.read_timeout = 10
            response = http.request_head(uri.request_uri)
            response.code
          rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError
            '500'
          end
        end
      end
    end
  end
end
