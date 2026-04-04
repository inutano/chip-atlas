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
  end

  def test_genomes
    get '/api/genomes'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_includes data, 'hg38'
    assert_includes data, 'TAIR10'
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

  def test_get_download_url
    get '/api/download_url', genome: 'hg38', track_class: 'Histone', track_subclass: 'H3K4me3',
                             cell_type_class: 'Blood', cell_type_subclass: '-', qval: '05'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/chip-atlas\.dbcls\.jp/, data['url'])
  end
end
