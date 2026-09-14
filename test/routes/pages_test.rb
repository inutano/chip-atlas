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

  SPRITE_SYMBOLS = %w[
    mountain glasses hand-holding-heart balance-scale-left bullseye
    compress-arrows-alt book robot github search info-circle question-circle
    spinner download dna chart-line chart-bar project-diagram
    external-link-alt user-edit tag server microscope flask file-alt eye cogs
  ].freeze

  def test_sprite_defines_every_symbol
    sprite = File.read(File.join(__dir__, '..', '..', 'public', 'icons', 'chip-atlas.svg'))
    SPRITE_SYMBOLS.each do |name|
      assert_includes sprite, %(id="#{name}"), "sprite is missing symbol #{name}"
    end
  end

  def test_sprite_is_served
    get '/icons/chip-atlas.svg'
    assert_equal 200, last_response.status
  end

  NAV_ICONS = {
    'peak_browser'        => 'glasses',
    'enrichment_analysis' => 'hand-holding-heart',
    'diff_analysis'       => 'balance-scale-left',
    'target_genes'        => 'bullseye',
    'colo'                => 'compress-arrows-alt',
    'publications'        => 'book',
    'agents'              => 'robot'
  }.freeze

  def test_navbar_links_carry_their_icons
    get '/'
    body = last_response.body
    NAV_ICONS.each_value do |icon|
      assert_includes body, "chip-atlas.svg##{icon}", "navbar is missing the #{icon} icon"
    end
    assert_includes body, 'chip-atlas.svg#github'
    assert_includes body, 'chip-atlas.svg#search'
  end

  def test_navbar_brand_is_the_mountain
    get '/'
    assert_includes last_response.body, 'chip-atlas.svg#mountain'
    refute_includes last_response.body, 'M8 1l2 5h5l-4 3 1.5 5L8 11 3.5 14 5 9 1 6h5z'
  end
end
