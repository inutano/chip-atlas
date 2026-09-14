# frozen_string_literal: true

require 'test_helper'

class PagesTest < Minitest::Test
  include Rack::Test::Methods

  def app
    ChipAtlasApp
  end

  PAGES = %w[
    / /peak_browser /search /colo /target_genes
    /enrichment_analysis /diff_analysis /publications /agents /demo
  ].freeze

  def test_all_pages_render_ok
    PAGES.each do |path|
      get path
      assert_equal 200, last_response.status, "#{path} did not return 200"
      assert_includes last_response.body, '<nav', "#{path} has no navbar"
      assert_includes last_response.body, '</html>', "#{path} is truncated"
    end
  end

  def test_layout_uses_fixed_width_container
    get '/'
    assert_includes last_response.body, 'class="container container-narrow"'
  end

  def test_stylesheet_uses_bootstrap3_primary
    css = File.read(File.join(__dir__, '..', '..', 'public', 'css', 'style.css'))
    assert_includes css, '#428bca', 'primary colour must match Bootstrap 3.2'
    refute_includes css, '#337ab7', 'Bootstrap 3.3 primary must not be used'
  end
end
