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
        ALLOWED_HOSTS.any? { |host| uri.host == host || uri.host&.end_with?(".#{host}") }
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

          def body_with_condition
            data = parsed_json
            halt 400, json_response({ error: 'condition object required' }) unless data['condition'].is_a?(Hash)
            validated_genome!(data['condition']['genome'])
            data
          end

          # API-53: genome used to be interpolated unchecked into outbound
          # URLs (a value like "util/lineNum.tsv#" or "a b" raised
          # URI::InvalidURIError deep inside LocationService/BedExtensionResolver,
          # an uncaught 500). Defaults to the query-string param so GET routes
          # can call it bare; POST routes pass the condition's genome explicitly.
          def validated_genome!(genome = params[:genome])
            return if genome.is_a?(String) && ChipAtlas::Experiment.genomes.key?(genome)

            halt 400, json_response({ error: "Unknown genome: #{genome.inspect}" })
          end

          # API-53: distance must be one of the UI's fixed set, not any
          # string the caller happens to send.
          def validated_distance!
            distance = params[:distance]
            return if ChipAtlas::Analysis::TARGET_GENES_DISTANCES.any? { |d| d[:id] == distance }

            halt 400, json_response({ error: "Unknown distance: #{distance.inspect}" })
          end
        end

        # === Classification endpoints ===

        app.get '/api/genomes' do
          cache_control :public, max_age: 86_400
          json_response(ChipAtlas::Experiment.list_of_genome)
        end

        app.get '/api/stats' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Experiment.stats)
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
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Analysis.colo_result_by_genome(params[:genome]))
        end

        app.get '/api/target_genes_index' do
          cache_control :public, max_age: 3600
          json_response(ChipAtlas::Analysis.target_genes_result)
        end

        app.get '/api/target_genes_distances' do
          cache_control :public, max_age: 86_400
          json_response(ChipAtlas::Analysis.target_genes_distances)
        end

        # === URL generation endpoints (GET for agents, POST for frontend) ===

        app.get '/api/igv_url' do
          halt 400, json_response({ error: 'genome and track_class required' }) unless params[:genome] && params[:track_class]
          validated_genome!
          url = ChipAtlas::LocationService.new(condition_from_params).igv_browsing_url
          json_response({ url: url })
        end

        app.post '/api/igv_url' do
          url = ChipAtlas::LocationService.new(body_with_condition).igv_browsing_url
          json_response({ url: url })
        end

        app.get '/api/download_url' do
          halt 400, json_response({ error: 'genome and track_class required' }) unless params[:genome] && params[:track_class]
          validated_genome!
          url = ChipAtlas::LocationService.new(condition_from_params).archive_url
          json_response({ url: url })
        end

        app.post '/api/download_url' do
          url = ChipAtlas::LocationService.new(body_with_condition).archive_url
          json_response({ url: url })
        end

        # Colocalization result data: parsed and sorted server-side from the
        # precomputed TSV (there is no JSON file on the data server for this
        # analysis, and never has been - see ChipAtlas::ColoTsv).
        app.get '/api/colo' do
          halt 400, json_response({ error: 'genome, track, and cell_type required' }) unless params[:genome] && params[:track] && params[:cell_type]
          validated_genome!
          svc = ChipAtlas::LocationService.new(condition_from_params)

          result = begin
            ChipAtlas::ColoTsv.result(tsv_url: svc.colo_tsv_url)
          rescue ChipAtlas::ColoTsv::ParseError => e
            halt 502, json_response({ error: "Colocalization data could not be parsed: #{e.message}" })
          end
          halt 404, json_response({ error: 'Colocalization data not found' }) unless result

          log_activity('colo', { genome: params[:genome], track: params[:track], cell_type: params[:cell_type] })
          json_response(result.merge(genome: params[:genome], track: params[:track], cell_type: params[:cell_type]))
        end

        # Colocalization file download (proxied from data server)
        app.get '/api/colo/download' do
          halt 400, json_response({ error: 'genome, track, cell_type, and format required' }) unless params[:genome] && params[:track] && params[:cell_type] && params[:format]
          validated_genome!
          svc = ChipAtlas::LocationService.new(condition_from_params)
          url = case params[:format]
                when 'tsv' then svc.colo_tsv_url
                when 'gml' then svc.colo_gml_url
                else halt 400, json_response({ error: "Unknown format: #{params[:format]}. Available: tsv, gml" })
                end

          # TG-15: the frontend probes this URL with HEAD before navigating,
          # purely to ask "does this exist?" - GML files run up to ~33 MB, so
          # answer that with a HEAD to the data server (DataProxy.exists?)
          # rather than pulling the whole body through `fetch` just to
          # discard it. Same status/body shape as the GET 404 below, so a
          # caller sees identical semantics from either verb.
          if request.head?
            halt 404, json_response({ error: 'File not found' }) unless ChipAtlas::DataProxy.exists?(url)
            content_type params[:format] == 'tsv' ? 'text/tab-separated-values' : 'application/xml'
            halt 200
          end

          body = ChipAtlas::DataProxy.fetch(url)
          halt 404, json_response({ error: 'File not found' }) unless body
          content_type params[:format] == 'tsv' ? 'text/tab-separated-values' : 'application/xml'
          attachment "#{params[:track]}.#{params[:cell_type]}.#{params[:format]}"
          body
        end

        # Target genes result data: parsed, sorted, and paginated server-side
        # from the precomputed TSV (there is no JSON file on the data
        # server for this analysis - see ChipAtlas::TargetGenesTsv).
        app.get '/api/target_genes' do
          halt 400, json_response({ error: 'genome, track, and distance required' }) unless params[:genome] && params[:track] && params[:distance]
          validated_genome!
          validated_distance!
          svc = ChipAtlas::LocationService.new(condition_from_params)

          result = begin
            ChipAtlas::TargetGenesTsv.result(
              genome: params[:genome], track: params[:track], distance: params[:distance],
              tsv_url: svc.target_genes_tsv_url,
              sort: params[:sort], order: params[:order], offset: params[:offset], limit: params[:limit],
              q: params[:q]
            )
          rescue ChipAtlas::TargetGenesTsv::UnknownSortColumn => e
            halt 400, json_response({ error: e.message })
          rescue ChipAtlas::TargetGenesTsv::ParseError => e
            halt 502, json_response({ error: "Target genes data could not be parsed: #{e.message}" })
          end
          halt 404, json_response({ error: 'Target genes data not found' }) unless result

          log_activity('target_genes', { genome: params[:genome], track: params[:track], distance: params[:distance], q: params[:q] })
          json_response(result)
        end

        # Target genes file download (proxied from data server)
        app.get '/api/target_genes/download' do
          halt 400, json_response({ error: 'genome, track, distance, and format required' }) unless params[:genome] && params[:track] && params[:distance] && params[:format]
          validated_genome!
          validated_distance!
          svc = ChipAtlas::LocationService.new(condition_from_params)
          url = case params[:format]
                when 'tsv' then svc.target_genes_tsv_url
                else halt 400, json_response({ error: "Unknown format: #{params[:format]}. Available: tsv" })
                end

          # TG-15: see the matching HEAD short-circuit in /api/colo/download
          # above.
          if request.head?
            halt 404, json_response({ error: 'File not found' }) unless ChipAtlas::DataProxy.exists?(url)
            content_type 'text/tab-separated-values'
            halt 200
          end

          body = ChipAtlas::DataProxy.fetch(url)
          halt 404, json_response({ error: 'File not found' }) unless body
          content_type 'text/tab-separated-values'
          attachment "#{params[:track]}.#{params[:distance]}.tsv"
          body
        end

        # === Internal endpoints (not in OpenAPI) ===

        app.get '/api/remote_url_status' do
          # Finding 5 (2026-09-24 final review): this route never set a
          # content type, so Sinatra defaulted it to text/html even though
          # the body is always a bare status-code string and public/
          # openapi.yaml documents text/plain -- set it up front so both the
          # 400 path below and the 200/synthetic-500 path after it agree
          # with the spec.
          content_type 'text/plain'
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
            # Only a genuine upstream response is safe to cache publicly for
            # an hour. A rescued exception below returns a synthetic '500'
            # that must not be cached - a transient blip would otherwise
            # hide the Comparative Profile section from every viewer for
            # that hour.
            cache_control :public, max_age: 3600
            response.code
          rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError,
                 Net::OpenTimeout, OpenSSL::SSL::SSLError, Errno::ECONNRESET, Errno::EHOSTUNREACH
            '500'
          end
        end
      end
    end
  end
end
