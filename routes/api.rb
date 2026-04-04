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
        # Static data endpoints (constants or cached, safe to cache in browser)
        app.get '/data/index_all_genome.json' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Experiment.cached_index_all_genome)
        end

        app.get '/data/list_of_genome.json' do
          cache_control :public, max_age: 86_400
          json_response(ChipAtlas::Experiment.list_of_genome.keys)
        end

        app.get '/data/list_of_experiment_types.json' do
          cache_control :public, max_age: 86_400
          json_response(ChipAtlas::Experiment.list_of_experiment_types)
        end

        app.get '/data/qval_range.json' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Bedfile.qval_range)
        end

        app.get '/data/target_genes_analysis.json' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Analysis.target_genes_result)
        end

        app.get '/data/number_of_lines.json' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Bedsize.dump)
        end

        # Dynamic data endpoints (query the database)
        app.get '/data/exp_metadata.json' do
          halt 400, json_response({ error: 'expid parameter required' }) unless params[:expid]
          json_response(ChipAtlas::Experiment.record_by_exp_id(params[:expid]))
        end

        app.get '/data/colo_analysis.json' do
          halt 400, json_response({ error: 'genome parameter required' }) unless params[:genome]
          json_response(ChipAtlas::Analysis.colo_result_by_genome(params[:genome]))
        end

        app.get '/data/index_subclass.json' do
          json_response(
            ChipAtlas::Experiment.get_subclass(
              params[:genome], params[:agClass], params[:clClass], params[:type]
            )
          )
        end

        # Deprecated bulk JSON endpoints
        app.get '/data/ExperimentList.json' do
          halt 410, json_response({ error: 'Use /data/search for experiment queries' })
        end

        app.get '/data/ExperimentList_adv.json' do
          halt 410, json_response({ error: 'Use /data/search for experiment queries' })
        end

        # Faceted search endpoints (query the database)
        app.get '/data/experiment_types' do
          json_response(ChipAtlas::Experiment.experiment_types(params[:genome], params[:clClass]))
        end

        app.get '/data/sample_types' do
          json_response(ChipAtlas::Experiment.sample_types(params[:genome], params[:agClass]))
        end

        app.get '/data/chip_antigen' do
          json_response(ChipAtlas::Experiment.chip_antigen(params[:genome], params[:agClass], params[:clClass]))
        end

        app.get '/data/cell_type' do
          json_response(ChipAtlas::Experiment.cell_type(params[:genome], params[:agClass], params[:clClass]))
        end

        app.get '/data/search' do
          query  = params[:q]
          genome = params[:genome]
          limit  = (params[:limit] || 20).to_i.clamp(1, 100)
          offset = (params[:offset] || 0).to_i
          json_response(ChipAtlas::ExperimentSearch.search(query, genome: genome, limit: limit, offset: offset))
        end

        app.get '/qvalue_range' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Bedfile.qval_range)
        end

        # POST endpoints
        app.post '/browse' do
          json = parsed_json
          url = ChipAtlas::LocationService.new(json).igv_browsing_url
          json_response({ 'url' => url })
        end

        app.post '/download' do
          json = parsed_json
          url = ChipAtlas::LocationService.new(json).archive_url
          json_response({ 'url' => url })
        end

        app.post '/colo' do
          json = parsed_json
          url = ChipAtlas::LocationService.new(json).colo_url(params[:type])
          json_response({ 'url' => url })
        end

        app.post '/target_genes' do
          json = parsed_json
          url = ChipAtlas::LocationService.new(json).target_genes_url(params[:type])
          json_response({ 'url' => url })
        end

        app.post '/diff_analysis_estimated_time' do
          data = parsed_json
          total_reads = ChipAtlas::Experiment.total_number_of_reads(data['ids']).to_i
          seconds = case data['analysis']
                    when 'dmr'      then 117.13 * Math.log(total_reads) - 2012.5 + 600
                    when 'diffbind' then 1.80e-6 * total_reads + 119.38 + 600
                    end
          minutes = (seconds && !seconds.infinite?) ? Rational(seconds, 60).to_f.round : nil
          json_response({ minutes: minutes })
        end

        app.get '/api/remoteUrlStatus' do
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
