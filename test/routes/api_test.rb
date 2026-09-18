# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../app'

class ApiTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    ChipAtlasApp
  end

  def setup
    seed_all
    # Set settings that are normally populated by the configure block
    # (skipped in test via SKIP_APP_CONFIGURE=1)
    ChipAtlasApp.set :list_of_genome, ChipAtlas::Experiment.list_of_genome
    ChipAtlasApp.set :list_of_experiment_types, ChipAtlas::Experiment.list_of_experiment_types
    # /api/download_url and /api/igv_url route through
    # LocationService#bed_url -> BedExtensionResolver, which does a live HEAD
    # probe unless stubbed. Stub it so this suite never touches the network.
    ChipAtlas::BedExtensionResolver.prober = ->(url) { url.end_with?('.bed') }
  end

  def teardown
    ChipAtlas::BedExtensionResolver.prober = nil
    super
  end

  def test_genomes
    get '/api/genomes'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_kind_of Hash, data
    assert_includes data.keys, 'hg38'
    assert_includes data.keys, 'TAIR12'
    assert_equal 'H. sapiens (hg38)', data['hg38']
  end

  def test_stats
    get '/api/stats'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_kind_of Hash, data
    %w[total_experiments total_experiments_formatted by_genome by_track_class].each do |key|
      assert data.key?(key), "Expected key '#{key}' in stats response"
    end
    assert_kind_of Integer, data['total_experiments']
    assert_kind_of Hash, data['by_genome']
    assert_kind_of Hash, data['by_track_class']
  end

  def test_track_classes_static
    get '/api/track_classes'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data.any? { |t| t['id'] == 'CUT&Tag' }
  end

  def test_track_classes_with_counts
    get '/api/track_classes', genome: 'hg38', cell_type_class: 'All cell types'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    histone = data.find { |d| d['id'] == 'Histone' }
    assert_equal 2, histone['count']
  end

  def test_cell_type_classes
    get '/api/cell_type_classes', genome: 'hg38', track_class: 'Histone'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'All cell types', data.first['id']
  end

  def test_track_subclasses
    get '/api/track_subclasses', genome: 'hg38', track_class: 'Histone', cell_type_class: 'All cell types'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal '-', data.first['id']
  end

  def test_cell_type_subclasses
    get '/api/cell_type_subclasses', genome: 'hg38', track_class: 'Histone', cell_type_class: 'Blood'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    k562 = data.find { |d| d['id'] == 'K-562' }
    assert k562
  end

  def test_experiment
    get '/api/experiment', experiment_id: 'SRX018625'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 1, data.size
    assert_equal 'SRX018625', data.first['experiment_id']
    assert_equal 'Histone', data.first['track_class']
  end

  def test_search
    DB.run <<-SQL
      INSERT INTO experiments_fts (experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes)
      VALUES ('SRX018625', '', '', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'H3K4me3 in K-562', '');
    SQL

    get '/api/search', q: 'K-562', genome: 'hg38', limit: '10'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data['total'] >= 1
  end

  def test_search_without_query_lists_experiments
    DB.run <<-SQL
      INSERT INTO experiments_fts (experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes)
      VALUES ('SRX018625', '', '', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'H3K4me3 in K-562', '');
    SQL

    get '/api/search?limit=2'
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_operator data['total'], :>, 0
  end

  def test_post_download_url
    post '/api/download_url', JSON.generate({
      condition: { genome: 'hg38', track_class: 'Histone', track_subclass: 'H3K4me3',
                   cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/chip-atlas\.dbcls\.jp/, data['url'])
  end

  def test_post_igv_url
    post '/api/igv_url', JSON.generate({
      condition: { genome: 'hg38', track_class: 'Histone', track_subclass: 'H3K4me3',
                   cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/localhost:60151/, data['url'])
  end

  def test_post_download_url_without_condition_returns_400
    post '/api/download_url', JSON.generate({}), 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
  end

  def test_post_igv_url_without_condition_returns_400
    post '/api/igv_url', JSON.generate({}), 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
  end

  def test_get_download_url
    get '/api/download_url', genome: 'hg38', track_class: 'Histone', track_subclass: 'H3K4me3',
                             cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/chip-atlas\.dbcls\.jp/, data['url'])
  end

  def test_target_genes_distances
    get '/api/target_genes_distances'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_kind_of Array, data
    assert_equal 3, data.size
    data.each do |item|
      assert item.key?('id'), "Expected key 'id' in distance option"
      assert item.key?('label'), "Expected key 'label' in distance option"
    end
  end

  # /api/target_genes proxies ChipAtlas::TargetGenesTsv, which fetches and
  # parses the precomputed TSV (there is no JSON file on the data server -
  # see task B2's brief). Stub its fetcher so this suite never touches the
  # network; TargetGenesTsv itself raises LiveFetchNotStubbed if a test
  # forgets to (see lib/services/target_genes_tsv.rb).
  TARGET_GENES_FIXTURE = File.read(File.join(__dir__, '..', 'fixtures', 'target_genes_sample.tsv'))

  def test_target_genes_returns_columns_rows_and_paging_metadata
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1', limit: 2

    assert last_response.ok?
    assert_equal 'application/json', last_response.content_type.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal %w[Target_genes Stat3|Average SRX361677|Astrocytes SRX400001|Neuron STRING], data['columns']
    assert_equal %w[Myc Stat3], data['rows'].map(&:first)
    assert_equal 5, data['total']
    assert_equal 0, data['offset']
    assert_equal 2, data['limit']
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_sort_and_order_params_are_honored
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1',
                              sort: 'SRX361677|Astrocytes', order: 'asc'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal %w[Socs3 Il6 Stat3 Bcl2 Myc], data['rows'].map(&:first)
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_unknown_sort_column_returns_400
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1', sort: 'NoSuchColumn'

    assert_equal 400, last_response.status
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  # This also doubles as a regression test for the shared not_found handler
  # (routes/pages.rb, see test/routes/pages_test.rb for the general case):
  # asserting the SPECIFIC 'Target genes data not found' message - not just
  # a 404 status - is what would fail if that handler's JSON-body guard
  # were ever reverted, since Sinatra would then silently replace this
  # body with the generic HTML not_found page.
  def test_target_genes_missing_combination_returns_404
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { nil }

    get '/api/target_genes', genome: 'mm10', track: 'NoSuchTrack', distance: '1'

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal 'Target genes data not found', data['error']
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_malformed_body_returns_502_distinguishable_from_404
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { 'not a real tsv, one column only' }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1'

    assert_equal 502, last_response.status
    data = JSON.parse(last_response.body)
    refute_equal 'Target genes data not found', data['error']
    assert_match(/could not be parsed/, data['error'])
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_limit_is_capped
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1', limit: 999_999

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal ChipAtlas::TargetGenesTsv::MAX_LIMIT, data['limit']
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_missing_params_returns_400
    get '/api/target_genes', genome: 'mm10', track: 'Stat3'
    assert_equal 400, last_response.status
  end

  # --- download routes: 404 body now carries a JSON error, not bare text ---
  #
  # /api/colo/download and /api/target_genes/download call
  # ChipAtlas::DataProxy.fetch directly (no fetcher hook - that's B5's/B2's
  # respective preview endpoints only). Under this suite's --network none,
  # the real Net::HTTP call fails and DataProxy.fetch rescues it to nil,
  # exactly like a genuinely missing file would - no stub needed to reach
  # the 404 path. These also serve as a second, independent regression
  # check for the shared not_found handler (see pages_test.rb), on routes
  # that have nothing to do with ChipAtlas::TargetGenesTsv.

  def test_colo_download_missing_file_returns_404_with_json_body
    get '/api/colo/download', genome: 'mm10', track: 'NoSuchTrack', cell_type: 'NoSuchCellType', format: 'tsv'

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal 'File not found', data['error']
  end

  def test_target_genes_download_missing_file_returns_404_with_json_body
    get '/api/target_genes/download', genome: 'mm10', track: 'NoSuchTrack', distance: '1', format: 'tsv'

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal 'File not found', data['error']
  end

  # /api/remote_url_status must rescue the fuller set of transient upstream
  # failures (matching lib/services/service_monitor.rb, plus ECONNRESET and
  # EHOSTUNREACH) rather than let them escape as an uncaught Sinatra 500 -
  # which would also mean the response is never cache_control'd publicly for
  # an hour (see the cache_control-ordering fix in the same endpoint).
  [OpenSSL::SSL::SSLError, Net::OpenTimeout, Errno::ECONNRESET, Errno::EHOSTUNREACH].each do |error_class|
    define_method("test_remote_url_status_rescues_#{error_class.name.gsub('::', '_')}") do
      original = Net::HTTP.instance_method(:request_head)
      Net::HTTP.define_method(:request_head) { |*| raise error_class, 'simulated upstream failure' }
      begin
        get '/api/remote_url_status', url: 'https://chip-atlas.dbcls.jp/data/probe.png'
        assert last_response.ok?, "expected a handled 200 response, got #{last_response.status}"
        assert_equal '500', last_response.body
      ensure
        Net::HTTP.define_method(:request_head, original)
      end
    end
  end

  def test_remote_url_status_does_not_cache_the_error_path
    original = Net::HTTP.instance_method(:request_head)
    Net::HTTP.define_method(:request_head) { |*| raise Errno::ECONNREFUSED, 'simulated' }
    begin
      get '/api/remote_url_status', url: 'https://chip-atlas.dbcls.jp/data/probe.png'
      assert_equal '500', last_response.body
      refute_match(/public/, last_response.headers['Cache-Control'].to_s,
                   'a transient upstream failure must not be cached publicly for an hour')
    ensure
      Net::HTTP.define_method(:request_head, original)
    end
  end

  def test_remote_url_status_caches_a_genuine_upstream_response
    original = Net::HTTP.instance_method(:request_head)
    fake_response = Net::HTTPOK.new('1.1', '200', 'OK')
    Net::HTTP.define_method(:request_head) { |*| fake_response }
    begin
      get '/api/remote_url_status', url: 'https://chip-atlas.dbcls.jp/data/probe.png'
      assert_equal '200', last_response.body
      assert_match(/public/, last_response.headers['Cache-Control'].to_s)
      assert_match(/max-age=3600/, last_response.headers['Cache-Control'].to_s)
    ensure
      Net::HTTP.define_method(:request_head, original)
    end
  end
end
