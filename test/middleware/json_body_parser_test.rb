# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/middleware/json_body_parser'

class JsonBodyParserTest < Minitest::Test
  include Rack::Test::Methods

  def app
    parser = ChipAtlas::JsonBodyParser
    Rack::Builder.new do
      use parser
      run ->(env) {
        body = env['parsed_body']
        [200, { 'content-type' => 'application/json' }, [JSON.generate({ parsed: body })]]
      }
    end
  end

  def test_valid_json_post
    post '/', JSON.generate({ key: 'value' }), 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal({ 'key' => 'value' }, data['parsed'])
  end

  def test_invalid_json_post_returns_400
    post '/', '{invalid json', 'CONTENT_TYPE' => 'application/json'

    assert_equal 400, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 'Invalid JSON', data['error']
  end

  def test_non_json_post_passes_through
    post '/', 'plain text body', 'CONTENT_TYPE' => 'text/plain'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_nil data['parsed']
  end

  def test_get_request_passes_through
    get '/'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_nil data['parsed']
  end

  def test_empty_json_body_passes_through
    post '/', '', 'CONTENT_TYPE' => 'application/json'

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_nil data['parsed']
  end
end
