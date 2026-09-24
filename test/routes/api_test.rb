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
    assert data.any? { |t| t['id'] == 'Histone' }
    # Task D2 (Q1): CUT&Tag/CUT&RUN have no menu entry of their own.
    refute data.any? { |t| t['id'] == 'CUT&Tag' }
    refute data.any? { |t| t['id'] == 'CUT&RUN' }
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
    assert_match(%r{genome=https://chip-atlas\.dbcls\.jp/data/genome/hg38/hg38\.json}, data['url'])
  end

  # The owner's report: IGV desktop has no bundled TAIR12 genome, so the
  # bare code (genome=TAIR12) silently fails to resolve. Every assembly's
  # genome= value must be the genome's own JSON URL end-to-end through the
  # route, not just at the LocationService unit level.
  def test_post_igv_url_for_tair12_uses_the_genome_json_url
    DB[:bedfiles].insert(
      filename: 'His.ALL.05.H3K4me3.AllCell', genome: 'TAIR12', track_class: 'Histone',
      track_subclass: 'H3K4me3', cell_type_class: 'All cell types', cell_type_subclass: '-',
      qval: '05', experiments: 'SRX000001', created_at: Time.now
    )
    ChipAtlas::BedExtensionResolver.prober = ->(url) { url.end_with?('.bed.gz') }

    post '/api/igv_url', JSON.generate({
      condition: { genome: 'TAIR12', track_class: 'Histone', track_subclass: 'H3K4me3',
                   cell_type_class: 'All cell types', cell_type_subclass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(%r{genome=https://chip-atlas\.dbcls\.jp/data/genome/TAIR12/TAIR12\.json}, data['url'])
  end

  def test_post_download_url_without_condition_returns_400
    post '/api/download_url', JSON.generate({}), 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
  end

  def test_post_igv_url_without_condition_returns_400
    post '/api/igv_url', JSON.generate({}), 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
  end

  def test_post_download_url_with_non_object_json_body_returns_400
    post '/api/download_url', JSON.generate([1, 2]), 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 'JSON body must be an object', data['error']
  end

  # API-53 / SV-... : genome is validated against ChipAtlas::Experiment.genomes
  # rather than interpolated unchecked into a URL (which used to raise
  # URI::InvalidURIError -> 500 for garbage like a path traversal attempt).
  def test_get_igv_url_invalid_genome_returns_400
    get '/api/igv_url', genome: 'util/lineNum.tsv#', track_class: 'Histone'
    assert_equal 400, last_response.status
    data = JSON.parse(last_response.body)
    assert_match(/Unknown genome/, data['error'])
  end

  def test_get_download_url_invalid_genome_returns_400
    get '/api/download_url', genome: 'util/lineNum.tsv#', track_class: 'Histone'
    assert_equal 400, last_response.status
  end

  def test_post_igv_url_invalid_genome_returns_400
    post '/api/igv_url', JSON.generate({
      condition: { genome: 'util/lineNum.tsv#', track_class: 'Histone', track_subclass: 'H3K4me3',
                   cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
  end

  def test_post_download_url_invalid_genome_returns_400
    post '/api/download_url', JSON.generate({
      condition: { genome: 'util/lineNum.tsv#', track_class: 'Histone', track_subclass: 'H3K4me3',
                   cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
  end

  # PB-19: Annotation tracks used to raise Bedfile::NotFound (uncaught, ->
  # 500) via /api/igv_url because the trackname lookup ran before the
  # cell_type_class: 'All cell types' merge that the filename lookup
  # already got. Both must now use the merged condition.
  def test_get_igv_url_annotation_tracks_returns_a_url_when_a_bedfile_matches
    DB[:bedfiles].insert(
      filename: 'cpg_island.hg38.bed', genome: 'hg38', track_class: 'Annotation tracks',
      track_subclass: 'CpG Islands', cell_type_class: 'All cell types', cell_type_subclass: '-',
      qval: 'anno', experiments: '', created_at: Time.now
    )

    get '/api/igv_url', genome: 'hg38', track_class: 'Annotation tracks', track_subclass: 'CpG Islands',
                         cell_type_class: 'NA', qval: 'anno'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match %r{genome=https://chip-atlas\.dbcls\.jp/data/genome/hg38/hg38\.json}, data['url']
    assert_match %r{annotations/hg38/}, data['url']
    assert_match(/&name=/, data['url'])
  end

  def test_post_igv_url_annotation_tracks_returns_null_url_when_no_bedfile_matches
    post '/api/igv_url', JSON.generate({
      condition: { genome: 'hg38', track_class: 'Annotation tracks', track_subclass: 'NoSuchSubclass',
                   cell_type_class: 'NA', qval: 'anno' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_nil data['url']
  end

  # Finding 1 (2026-09-24 final review): GET /api/igv_url must have the same
  # {"url":null} contract as POST and as /api/download_url for a
  # non-Annotation track class with no matching bedfile -- not a URL with an
  # empty file= parameter (LocationService#igv_browsing_url's `else` branch
  # used to interpolate bed_url, which had already rescued NotFound to nil).
  def test_get_igv_url_returns_null_url_when_no_bedfile_matches
    get '/api/igv_url', genome: 'hg38', track_class: 'Histone', track_subclass: 'NONEXISTENT',
                         cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05'

    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_nil data['url']
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

  def test_target_genes_q_filters_before_paging_and_reports_the_filtered_total
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1', q: 'oc', limit: 2

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal %w[Socs3], data['rows'].map(&:first)
    assert_equal 1, data['total'], '`total` must reflect the filtered set, not the unfiltered file'
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_q_is_case_insensitive_substring
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1', q: 'MYC'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal %w[Myc], data['rows'].map(&:first)
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_q_absent_behaves_exactly_as_today
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 5, data['total']
  ensure
    ChipAtlas::TargetGenesTsv.fetcher = nil
  end

  def test_target_genes_q_with_no_matches_returns_200_with_empty_rows_and_zero_total
    ChipAtlas::TargetGenesTsv.fetcher = ->(_url) { TARGET_GENES_FIXTURE }

    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '1', q: 'NoSuchGene'

    assert last_response.ok?, 'a filter with no matches is not an error - it is a valid, empty result'
    data = JSON.parse(last_response.body)
    assert_equal [], data['rows']
    assert_equal 0, data['total']
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

  def test_target_genes_invalid_genome_returns_400
    get '/api/target_genes', genome: 'util/lineNum.tsv#', track: 'Stat3', distance: '1'
    assert_equal 400, last_response.status
  end

  def test_target_genes_invalid_distance_returns_400
    get '/api/target_genes', genome: 'mm10', track: 'Stat3', distance: '7'
    assert_equal 400, last_response.status
  end

  # /api/colo proxies ChipAtlas::ColoTsv, which fetches and parses the
  # precomputed TSV (there is no JSON file on the data server for this
  # analysis, and never has been - see task B5's brief and
  # lib/services/colo_tsv.rb). Stub its fetcher so this suite never touches
  # the network; ColoTsv itself raises LiveFetchNotStubbed if a test forgets
  # to.
  COLO_FIXTURE = File.read(File.join(__dir__, '..', 'fixtures', 'colo_sample.tsv'))

  def test_colo_returns_columns_rows_sorted_by_average_descending
    ChipAtlas::ColoTsv.fetcher = ->(_url) { COLO_FIXTURE }

    get '/api/colo', genome: 'hg38', track: 'Stat3', cell_type: 'CellA'

    assert last_response.ok?
    assert_equal 'application/json', last_response.content_type.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal %w[Experiment Cell_subclass Protein Stat3|Average SRX111111|CellA SRX222222|CellB STRING],
                 data['columns']
    assert_equal %w[SRX111111 SRX100001 SRX100003 SRX100002], data['rows'].map(&:first)
    assert_equal 4, data['total']
    assert_equal 'hg38', data['genome']
    assert_equal 'Stat3', data['track']
    assert_equal 'CellA', data['cell_type']
  ensure
    ChipAtlas::ColoTsv.fetcher = nil
  end

  def test_colo_missing_combination_returns_404
    ChipAtlas::ColoTsv.fetcher = ->(_url) { nil }

    get '/api/colo', genome: 'hg38', track: 'NoSuchTrack', cell_type: 'NoSuchCellType'

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal 'Colocalization data not found', data['error']
  ensure
    ChipAtlas::ColoTsv.fetcher = nil
  end

  def test_colo_malformed_body_returns_502_distinguishable_from_404
    ChipAtlas::ColoTsv.fetcher = ->(_url) { "Experiment\tCell_subclass\tProtein\n" }

    get '/api/colo', genome: 'hg38', track: 'Stat3', cell_type: 'CellA'

    assert_equal 502, last_response.status
    data = JSON.parse(last_response.body)
    refute_equal 'Colocalization data not found', data['error']
    assert_match(/could not be parsed/, data['error'])
  ensure
    ChipAtlas::ColoTsv.fetcher = nil
  end

  def test_colo_missing_params_returns_400
    get '/api/colo', genome: 'hg38', track: 'Stat3'
    assert_equal 400, last_response.status
  end

  def test_colo_invalid_genome_returns_400
    get '/api/colo', genome: 'util/lineNum.tsv#', track: 'Stat3', cell_type: 'CellA'
    assert_equal 400, last_response.status
  end

  # --- download routes: 404 body now carries a JSON error, not bare text ---
  #
  # /api/colo/download and /api/target_genes/download call
  # ChipAtlas::DataProxy.fetch directly (no ColoTsv/TargetGenesTsv fetcher
  # hook - that's B5's/B2's respective preview endpoints only). DataProxy
  # itself now carries the same fetcher= seam and
  # raise_if_unstubbed_under_test! guard as ColoTsv/TargetGenesTsv, so these
  # stub it directly rather than relying on the sandbox's --network none:
  # that flag only isolates local runs (this repo's own test.sh), while CI
  # (.github/workflows/ci.yml) runs the Ruby suite on a GitHub-hosted
  # runner with no network isolation at all - without a stub, an unstubbed
  # DataProxy.fetch there would either raise (good - loud failure) or, if
  # the guard were missing, make a real HTTPS request to
  # chip-atlas.dbcls.jp that happens to 404 and pass by accident. These
  # also serve as a second, independent regression check for the shared
  # not_found handler (see pages_test.rb), on routes that have nothing to
  # do with ChipAtlas::TargetGenesTsv.

  def test_colo_download_missing_file_returns_404_with_json_body
    ChipAtlas::DataProxy.fetcher = ->(_url) { nil }

    get '/api/colo/download', genome: 'mm10', track: 'NoSuchTrack', cell_type: 'NoSuchCellType', format: 'tsv'

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal 'File not found', data['error']
  ensure
    ChipAtlas::DataProxy.fetcher = nil
  end

  # API-53: a genome containing '/', '#', '..' etc. used to be interpolated
  # straight into the outbound archive URL.
  def test_colo_download_invalid_genome_returns_400
    get '/api/colo/download', genome: 'util/lineNum.tsv#', track: 'x', cell_type: 'y', format: 'tsv'
    assert_equal 400, last_response.status
  end

  def test_target_genes_download_missing_file_returns_404_with_json_body
    ChipAtlas::DataProxy.fetcher = ->(_url) { nil }

    get '/api/target_genes/download', genome: 'mm10', track: 'NoSuchTrack', distance: '1', format: 'tsv'

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal 'File not found', data['error']
  ensure
    ChipAtlas::DataProxy.fetcher = nil
  end

  def test_target_genes_download_invalid_genome_returns_400
    get '/api/target_genes/download', genome: 'util/lineNum.tsv#', track: 'x', distance: '1', format: 'tsv'
    assert_equal 400, last_response.status
  end

  def test_target_genes_download_invalid_distance_returns_400
    get '/api/target_genes/download', genome: 'mm10', track: 'x', distance: '7', format: 'tsv'
    assert_equal 400, last_response.status
  end

  # --- HEAD requests (TG-15) ---
  #
  # The frontend probes these download URLs with HEAD before navigating, to
  # show an inline "No data found" message instead of navigating the whole
  # browser to a 404 JSON body. Sinatra maps HEAD to GET automatically, but a
  # GML file can run to ~33 MB, so both routes short-circuit a HEAD request
  # to a HEAD-only existence probe (DataProxy.exists?) rather than pulling
  # the whole body through DataProxy.fetch first (see routes/api.rb).
  #
  # These stub only `exists_fetcher=`, leaving `fetcher=` unset. If a route
  # ever regressed to falling through to the full `fetch` path for a HEAD
  # request, DataProxy.fetch would find no fetcher stubbed under
  # RACK_ENV=test and raise LiveFetchNotStubbed (Sinatra's test-mode
  # raise_errors is on by default - see jobs_test.rb's note on the same
  # behaviour) - failing these loudly rather than passing by accident.

  def test_colo_download_head_returns_200_via_the_lightweight_existence_probe
    ChipAtlas::DataProxy.exists_fetcher = ->(_url) { true }

    head '/api/colo/download', genome: 'mm10', track: 'Stat3', cell_type: 'CellA', format: 'gml'

    assert_equal 200, last_response.status
    assert_empty last_response.body
  ensure
    ChipAtlas::DataProxy.exists_fetcher = nil
  end

  def test_colo_download_head_missing_file_returns_404_without_the_full_fetch
    ChipAtlas::DataProxy.exists_fetcher = ->(_url) { false }

    head '/api/colo/download', genome: 'mm10', track: 'NoSuchTrack', cell_type: 'NoSuchCellType', format: 'tsv'

    assert_equal 404, last_response.status
  ensure
    ChipAtlas::DataProxy.exists_fetcher = nil
  end

  def test_target_genes_download_head_returns_200_via_the_lightweight_existence_probe
    ChipAtlas::DataProxy.exists_fetcher = ->(_url) { true }

    head '/api/target_genes/download', genome: 'mm10', track: 'Stat3', distance: '1', format: 'tsv'

    assert_equal 200, last_response.status
    assert_empty last_response.body
  ensure
    ChipAtlas::DataProxy.exists_fetcher = nil
  end

  def test_target_genes_download_head_missing_file_returns_404_without_the_full_fetch
    ChipAtlas::DataProxy.exists_fetcher = ->(_url) { false }

    head '/api/target_genes/download', genome: 'ce11', track: 'wdr-5', distance: '1', format: 'tsv'

    assert_equal 404, last_response.status
  ensure
    ChipAtlas::DataProxy.exists_fetcher = nil
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

  # Finding 5 (2026-09-24 final review): the route never set a content type,
  # so it defaulted to text/html even though the body is always a bare
  # status-code string and public/openapi.yaml documents text/plain.
  def test_remote_url_status_content_type_is_text_plain
    original = Net::HTTP.instance_method(:request_head)
    fake_response = Net::HTTPOK.new('1.1', '200', 'OK')
    Net::HTTP.define_method(:request_head) { |*| fake_response }
    begin
      get '/api/remote_url_status', url: 'https://chip-atlas.dbcls.jp/data/probe.png'
      assert_equal 'text/plain', last_response.content_type.to_s.split(';').first
    ensure
      Net::HTTP.define_method(:request_head, original)
    end
  end

  def test_remote_url_status_content_type_is_text_plain_on_the_400_path_too
    get '/api/remote_url_status', url: 'https://evil.example.com/probe.png'
    assert_equal 400, last_response.status
    assert_equal 'text/plain', last_response.content_type.to_s.split(';').first
  end
  # --- /api/colo_index: both directions, and no literal "-" in either ---

  def test_colo_index_offers_both_directions
    get '/api/colo_index?genome=hg38'

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)['hg38']
    assert_equal %w[K-562 HeLa-S3 GM12878], body['track']['CTCF']
    assert_includes body['cell_type']['K-562'], 'CTCF'
    assert_includes body['cell_type']['K-562'], 'H3K4me3'
  end

  def test_colo_index_never_offers_a_literal_dash_as_a_cell_type
    # The reverse index used to collapse to a single "-" because a cell_list
    # of "-" splits to ["-"]. Direct API consumers saw that even while the
    # page-level gate hid it from users, so this asserts on the endpoint.
    get '/api/colo_index?genome=hg38'

    body = JSON.parse(last_response.body)['hg38']
    refute_includes body['cell_type'].keys, '-'
    refute_includes body['track'].keys, 'NOCOLO'
    body['track'].each_value { |cells| refute_includes cells, '-' }
  end

  def test_colo_index_is_empty_for_a_genome_with_no_colo_data
    get '/api/colo_index?genome=TAIR12'

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)['TAIR12']
    assert_empty body['track']
    assert_empty body['cell_type']
  end

  def test_target_genes_index_covers_every_genome_with_rows
    get '/api/target_genes_index'

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_includes body['hg38'], 'CTCF'
    # A "-" cell_list says nothing about Target Genes: NOCOLO is flagged "+"
    # and must still be offered here.
    assert_includes body['hg38'], 'NOCOLO'
    assert_includes body['TAIR12'], 'AGL20'
  end
end
