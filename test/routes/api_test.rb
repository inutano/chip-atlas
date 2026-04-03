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

  def test_list_of_genome
    get '/data/list_of_genome.json'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_includes data, 'hg38'
    assert_includes data, 'TAIR10'
  end

  def test_list_of_experiment_types
    get '/data/list_of_experiment_types.json'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data.any? { |t| t['id'] == 'CUT&Tag' }
  end

  def test_experiment_types_with_counts
    get '/data/experiment_types', genome: 'hg38', clClass: 'All cell types'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    histone = data.find { |d| d['id'] == 'Histone' }
    assert_equal 2, histone['count']
  end

  def test_sample_types
    get '/data/sample_types', genome: 'hg38', agClass: 'Histone'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'All cell types', data.first['id']
  end

  def test_chip_antigen
    get '/data/chip_antigen', genome: 'hg38', agClass: 'Histone', clClass: 'All cell types'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal '-', data.first['id']
  end

  def test_cell_type
    get '/data/cell_type', genome: 'hg38', agClass: 'Histone', clClass: 'Blood'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    k562 = data.find { |d| d['id'] == 'K-562' }
    assert k562
  end

  def test_exp_metadata
    get '/data/exp_metadata.json', expid: 'SRX018625'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 1, data.size
    assert_equal 'SRX018625', data.first['expid']
    assert_equal 'Histone', data.first['agClass']
  end

  def test_search
    DB.run <<-SQL
      INSERT INTO experiments_fts (exp_id, sra_id, geo_id, genome, ag_class, ag_sub_class, cl_class, cl_sub_class, title, attributes)
      VALUES ('SRX018625', '', '', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'H3K4me3 in K-562', '');
    SQL

    get '/data/search', q: 'K-562', genome: 'hg38', limit: '10'
    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert data['total'] >= 1
  end

  def test_post_download
    post '/download', JSON.generate({
      condition: { genome: 'hg38', agClass: 'Histone', agSubClass: 'H3K4me3',
                   clClass: 'Blood', clSubClass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/chip-atlas\.dbcls\.jp/, data['url'])
  end

  def test_post_browse
    post '/browse', JSON.generate({
      condition: { genome: 'hg38', agClass: 'Histone', agSubClass: 'H3K4me3',
                   clClass: 'Blood', clSubClass: '-', qval: '05' }
    }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_match(/localhost:60151/, data['url'])
  end
end
