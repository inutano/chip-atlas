# frozen_string_literal: true

require 'test_helper'

class PagesTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    ChipAtlasApp
  end

  PAGES = %w[
    / /peak_browser /search /colo /colo_result /target_genes /target_genes_result
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

  # SHELL-20: kramdown's GFM mode has no bare-URL autolink option (unlike
  # production's redcarpet, which used `autolink: true`), so the "To cite"
  # DOIs and web-tool URL in publications.markdown were rewritten as
  # `<http://...>` autolinks rather than left as inert plain text.
  def test_publications_citation_dois_are_clickable_links
    get '/publications'
    body = last_response.body
    assert_includes body, 'href="http://dx.doi.org/10.1093/nar/gkae358"'
    assert_includes body, 'href="http://dx.doi.org/10.1093/nar/gkac199"'
    assert_includes body, 'href="http://dx.doi.org/10.15252/embr.201846255"'
    assert_includes body, 'href="https://chip-atlas.org"'
  end

  def test_demo_llms_txt_url_is_a_clickable_link
    get '/demo'
    assert_includes last_response.body, 'href="https://chip-atlas.org/llms.txt"'
  end

  # SHELL-20: production hand-edits its deployed updates.markdown, so this
  # repo's copy still carried an old maintenance notice as a dead HTML
  # comment (invisible on the rendered page, but present in the response
  # body) - stale content with no reason to still ship.
  def test_updates_markdown_stale_maintenance_comment_is_gone
    get '/'
    refute_includes last_response.body, 'Enrichment analysis will be temporarily unavailable'
  end

  # SHELL-02: the home page has no way to announce a feature outage now that
  # production's hand-edited red notice has no equivalent workflow here (see
  # frontend/pages/homepage.ts). The container starts hidden and empty;
  # homepage.ts fills and unhides it from GET /status client-side.
  def test_homepage_has_a_service_notice_container
    get '/'
    assert_includes last_response.body, '<div id="service-notice" hidden></div>'
  end

  def test_stylesheet_uses_bootstrap3_primary
    css = File.read(File.join(__dir__, '..', '..', 'public', 'css', 'style.css'))
    assert_includes css, '#428bca', 'primary colour must match Bootstrap 3.2'
    refute_includes css, '#337ab7', 'Bootstrap 3.3 primary must not be used'
  end

  # SHELL-34: Bootstrap 5's .popover-body defaults to white-space: normal, so
  # a multi-line ⓘ helpText string (e.g. Enrichment Analysis's "Gene list"
  # bullet list) collapsed into one run-on paragraph. --bs-popover-max-width
  # is the CSS variable Bootstrap 5.3's own .popover reads for its width.
  def test_stylesheet_preserves_popover_line_breaks_and_widens_them
    css = File.read(File.join(__dir__, '..', '..', 'public', 'css', 'style.css'))
    assert_includes css, '--bs-popover-max-width: 24rem'
    assert_includes css, 'white-space: pre-line'
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
    'publications'        => 'book'
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

  def test_pages_have_a_page_header_with_the_mountain
    %w[/ /peak_browser /search /colo /target_genes
       /enrichment_analysis /diff_analysis].each do |path|
      get path
      assert_includes last_response.body, 'class="page-header"', "#{path} has no page header"
      assert_includes last_response.body, 'chip-atlas.svg#mountain', "#{path} h1 has no mountain"
    end
  end

  def test_stylesheet_forces_navbar_links_white
    css = File.read(File.join(__dir__, '..', '..', 'public', 'css', 'style.css'))
    assert_includes css, '.navbar-dark .navbar-nav .nav-link,', 'non-active navbar links must be forced to pure white, matching production'
    assert_includes css, '.navbar-right-stack .nav-link:hover,', 'navbar hover/focus state must stay pure white, not the dim Bootstrap default'
  end

  def test_navbar_has_no_experiment_id_form
    get '/'
    body = last_response.body
    refute_includes body, 'jumpToExperiment', 'R11: the navbar experiment-ID lookup form must be gone'
    refute_includes body, 'navbar-id-form', 'R11: the navbar experiment-ID lookup form must be gone'
    assert_includes body, 'nav-search-link', 'R11: the Search item must be styled as a standalone link'
  end

  FEATURE_ICONS = {
    '/peak_browser'        => 'glasses',
    '/enrichment_analysis' => 'hand-holding-heart',
    '/diff_analysis'       => 'balance-scale-left',
    '/target_genes'        => 'bullseye',
    '/colo'                => 'compress-arrows-alt',
    '/search'              => 'search'
  }.freeze

  def test_homepage_cards_use_glyphs_not_emoji
    get '/'
    body = last_response.body
    FEATURE_ICONS.each_value do |icon|
      assert_includes body, "chip-atlas.svg##{icon}"
    end
    refute_includes body, '&#x1F50D;', 'magnifier emoji must be gone'
    refute_includes body, '&#x2764;',  'heart emoji must be gone'
    assert_includes body, 'class="jumbotron"'
  end

  def test_action_buttons_are_solid_and_full_width
    get '/peak_browser'
    body = last_response.body
    assert_includes body, 'Download BED file'
    refute_includes body, 'btn-outline-primary'
    assert_includes body, 'btn-block'
  end

  VIEW_ICONS = %w[
    file-alt tag microscope user-edit flask server cogs dna book
    eye chart-line download external-link-alt
  ].freeze

  def test_experiment_page_headings_carry_icons
    seed_experiments
    seed_sra_cache
    get '/view?id=SRX018625'
    assert_equal 200, last_response.status
    VIEW_ICONS.each do |icon|
      assert_includes last_response.body, "chip-atlas.svg##{icon}",
                       "experiment page is missing the #{icon} icon"
    end
  end

  def test_experiment_page_has_a_comparative_profile_section
    seed_experiments
    seed_sra_cache
    get '/view?id=SRX018625'
    body = last_response.body
    assert_includes body, 'Experiment Comparative Profile'
    assert_includes body, 'distribution/png/SRX018625.dist.png'
    assert_includes body, 'correlation/png/SRX018625.cor.png'
    assert_includes body, 'id="statistics-panel"'
  end

  # SV-27: experiment.ts hides this whole button group client-side for
  # Bisulfite-Seq experiments (no Colo/Target Genes data exists for them) —
  # this just pins that the server-rendered markup still gives it something
  # to find and hide, regardless of which experiment is loaded.
  def test_experiment_page_analyze_button_group_has_an_id_hook
    seed_experiments
    seed_sra_cache
    get '/view?id=SRX018625'
    assert_includes last_response.body, 'id="analyze-dropdown"'
  end

  def test_peak_browser_has_five_numbered_panels
    get '/peak_browser'
    body = last_response.body
    assert_includes body, '1. Track type class'
    assert_includes body, '2. Cell type Class'
    assert_includes body, '3. Threshold for Significance'
    assert_includes body, 'Track type (optional)'
    assert_includes body, 'Cell type (optional)'
    assert_includes body, 'class="card"'
  end

  def test_peak_browser_has_a_subclass_warning_container_above_the_panels
    get '/peak_browser'
    body = last_response.body
    assert_includes body, '<div class="panel-message" id="subclass-warning"></div>'
    # Not just present: it must sit above the panels' row, not merely
    # somewhere on the page (the page has other unrelated `class="row"`
    # elements below, in the footer).
    assert_operator body.index('id="subclass-warning"'), :<, body.index('class="row"'),
                     'the warning container must appear above the panels row'
  end

  def test_peak_browser_igv_help_link_is_an_info_popover_not_a_wiki_link
    get '/peak_browser'
    body = last_response.body
    assert_includes body, 'Error connecting to IGV?'
    assert_includes body, 'data-info="igv"'
    assert_includes body, 'class="info-btn igv-help"'
    refute_includes body, 'chip-atlas/wiki#igv_doc', 'PB-21: the dead wiki anchor link must be gone'
  end

  EA_PANELS = [
    '1. Experiment type', '2. Cell type Class', '3. Threshold for Significance',
    '4. Enter dataset A', '5. Enter dataset B', '6. Analysis description'
  ].freeze

  def test_enrichment_analysis_has_six_numbered_panels
    get '/enrichment_analysis'
    EA_PANELS.each { |h| assert_includes last_response.body, h }
  end

  def test_enrichment_analysis_seeds_title_placeholders
    get '/enrichment_analysis'
    body = last_response.body
    assert_includes body, 'value="My project"'
    assert_includes body, 'value="Dataset A"'
    assert_includes body, 'value="Dataset B"'
    assert_includes body, 'Try with example'
  end

  # Task 8 (R3/R4, EA-14/EA-17): panel 5 follows production again. The two
  # gene-list-only choices are hidden rows rather than disabled radios, so
  # their labels go back to production's wording instead of carrying a
  # "(gene-list mode only)" explanation of a greyed-out control that no
  # longer exists; and dataset B gets its own "Try with example" link, in
  # the same row as its file picker so both appear exactly when dataset B
  # takes input. frontend/pages/enrichment-analysis.ts's
  # syncDatasetBVisibility toggles #dataB-file-row and the four .form-check
  # wrappers - this pins that the ERB still ships them.
  def test_enrichment_analysis_dataset_b_choices_and_example_link
    get '/enrichment_analysis'
    body = last_response.body
    assert_includes body, 'id="try-example-b"'
    assert_includes body, 'id="dataB-file-row"'
    assert_includes body, 'Refseq coding genes (excluding dataset A)'
    refute_includes body, 'gene-list mode only',
                    'R3: the gene-list-only rows are hidden now, not disabled-and-labelled'
  end

  # Task 7 (EA-15): count-table mode hides panel 5's radios/permutation/
  # textarea/file picker behind #dataB-panel-body and shows the single
  # #count-mode-note line instead; panel 6's Dataset A/B title inputs are
  # wrapped in #dataset-titles so both can be hidden together. All three ids
  # are what frontend/pages/enrichment-analysis.ts's syncDatasetBVisibility
  # toggles - this only pins that the ERB still gives it something to find.
  def test_enrichment_analysis_has_count_mode_ids
    get '/enrichment_analysis'
    body = last_response.body
    assert_includes body, 'id="dataB-panel-body"'
    # Pins the `hidden` attribute alongside the id in the server-rendered
    # markup, not just the id's presence - #count-mode-note must start
    # hidden (syncDatasetBVisibility only reveals it once JS runs and
    # confirms count mode).
    assert_includes body, '<p id="count-mode-note" class="text-muted small mb-0" hidden>'
    assert_includes body, 'Not required for gene count table analysis'
    assert_includes body, 'id="dataset-titles"'
  end

  # Task 7 (EA-27): validation failures are written into #submit-status,
  # whose message can contain production's multi-line "Acceptable
  # characters are:\n- ..." text - it needs `white-space: pre-line` or the
  # newlines collapse to spaces.
  def test_enrichment_analysis_submit_status_preserves_newlines
    get '/enrichment_analysis'
    assert_includes last_response.body, 'white-space: pre-line'
  end

  # EA-26: the setup page's node-status link had drifted to a 404
  # (.../guides/software/GridEngine/) while the result page kept production's
  # working link. Both must point at the same, live URL.
  def test_enrichment_analysis_node_status_link_matches_production
    get '/enrichment_analysis'
    body = last_response.body
    assert_includes body, 'node status (epyc.q)'
    assert_includes body, 'href="https://sc.ddbj.nig.ac.jp/en/operation/job_queue_status/"'
    refute_includes body, 'GridEngine'
  end

  # EA-36/SHELL-39: production disabled its submit button and alerted when
  # the compute backend was down, checked on page load. This page had no
  # equivalent - restored via frontend/pages/enrichment-analysis.ts's
  # checkJobAvailability + this notice element, the same mechanism
  # views/diff_analysis.erb already uses.
  def test_enrichment_analysis_has_unavailable_notice
    get '/enrichment_analysis'
    assert_includes last_response.body,
                     '<div id="unavailable-notice" class="alert alert-warning small mb-2" role="alert" hidden></div>'
  end

  def test_target_genes_has_an_antigen_list_box
    get '/target_genes'
    body = last_response.body
    assert_includes body, '1. Choose Antigen'
    assert_includes body, '2. Choose Distance from TSS'
    assert_includes body, 'id="antigen-list"'
    assert_includes body, 'class="card"'
  end

  # TG-15: before navigating to the download endpoint, target-genes.ts
  # probes it with HEAD and, if it 404s, reports it here instead of
  # navigating the browser to a raw JSON error body.
  def test_target_genes_has_an_action_status_container
    get '/target_genes'
    assert_includes last_response.body,
                     '<div id="action-status" class="text-muted small mt-2" aria-live="polite"></div>'
  end

  def test_target_genes_result_has_distance_switch_legend_and_download_link
    get '/target_genes_result'
    body = last_response.body
    assert_includes body, 'id="distance-switch"'
    assert_includes body, 'data-distance="1"'
    assert_includes body, 'data-distance="5"'
    assert_includes body, 'data-distance="10"'
    assert_includes body, 'class="tg-legend"'
    assert_includes body, 'id="download-tsv"'
    assert_includes body, 'chip-atlas.svg#download'
  end

  # #gene-search's maxlength is rendered from @gene_search_max_length
  # (set in routes/pages.rb from ChipAtlas::TargetGenesTsv::MAX_QUERY_LENGTH)
  # rather than a second literal hardcoded in the ERB - this asserts the two
  # actually stay equal rather than merely trusting the wiring, the same
  # kind of two-representations-of-one-choice drift this codebase has
  # already been bitten by elsewhere (see the significance-threshold /
  # file-code encoding history).
  def test_gene_search_maxlength_matches_the_server_side_query_cap
    get '/target_genes_result'
    body = last_response.body
    assert_includes body, "maxlength=\"#{ChipAtlas::TargetGenesTsv::MAX_QUERY_LENGTH}\""
  end

  def test_target_genes_result_has_a_paginated_expandable_result_table
    get '/target_genes_result'
    body = last_response.body
    assert_includes body, 'id="result-table-wrap"'
    assert_includes body, 'id="result-thead-row"'
    assert_includes body, 'id="result-tbody"'
    assert_includes body, 'id="experiments-toggle"'
    assert_includes body, '<summary'
    assert_includes body, 'id="page-prev"'
    assert_includes body, 'id="page-next"'
    assert_includes body, 'id="page-indicator"'
    assert_includes body, 'id="row-count"'
    assert_includes body, 'id="sort-fallback-note"'
  end

  def test_diff_analysis_uses_cards
    get '/diff_analysis'
    assert_includes last_response.body, 'class="card"'
  end

  def test_diff_analysis_has_info_buttons_examples_and_node_status
    get '/diff_analysis'
    body = last_response.body
    assert_includes body, '4. Analysis description'
    assert_includes body, 'data-info="project-title"'
    assert_includes body, 'data-info="dataset-a-title"'
    assert_includes body, 'data-info="dataset-b-title"'
    assert_includes body, 'Try with example'
    assert_includes body, 'id="try-example-a"'
    assert_includes body, 'id="try-example-b"'
    assert_includes body, 'node status (epyc.q)'
    assert_includes body, 'sc.ddbj.nig.ac.jp/en/operation/job_queue_status/'
    assert_includes body, 'id="estimated-run-time"'
  end

  def test_diff_analysis_panel_headings_match_production
    # DA-08/DA-15: headings drifted to "Dataset A/B (Experiment IDs)", which
    # left the dataset-title ⓘ help text (frontend/pages/diff-analysis.ts)
    # referencing a heading that no longer existed. Restored to production's
    # wording rather than rewriting the help text.
    get '/diff_analysis'
    body = last_response.body
    assert_includes body, '2. Enter dataset A'
    assert_includes body, '3. Enter dataset B'
    refute_includes body, 'Dataset A (Experiment IDs)'
    refute_includes body, 'Dataset B (Experiment IDs)'
  end

  def test_diff_analysis_title_inputs_are_empty_in_markup
    # Production seeds "My project" / "dataset A" / "dataset B" via JS
    # (diff_analysis.js), not in server-rendered markup. Unlike Enrichment
    # Analysis's panel, these inputs must render with no value attribute.
    get '/diff_analysis'
    body = last_response.body
    refute_includes body, 'value="My project"'
    refute_includes body, 'value="dataset A"'
    refute_includes body, 'value="dataset B"'
  end

  def test_colo_has_paired_list_boxes_and_three_column_panels
    get '/colo'
    body = last_response.body
    assert_includes body, '1. Search mode'
    assert_includes body, 'id="primary-input"'
    assert_includes body, 'id="primary-list"'
    assert_includes body, 'id="secondary-input"'
    assert_includes body, 'id="secondary-list"'
    assert_includes body, 'col-md-3'
    refute_includes body, 'col-md-4', '/colo panels must match production col-md-3, not col-md-4'
  end

  # TG-15 (same pattern applied to Colo's two download buttons): colo.ts
  # probes each download endpoint with HEAD first and reports a 404 here
  # instead of navigating the browser to a raw JSON error body.
  def test_colo_has_an_action_status_container
    get '/colo'
    assert_includes last_response.body,
                     '<div id="action-status" class="text-muted small mt-2" aria-live="polite"></div>'
  end

  def test_colo_ships_a_live_picker_with_no_unavailable_notice
    # The picker was gated behind an honest-unavailable notice while the
    # colocalization index had no source. The regenerated analysisList.tab
    # supplies one (see lib/models/analysis.rb), so the gate and its notice
    # are gone and the picker ships live.
    get '/colo'
    body = last_response.body
    assert_includes body, 'id="colo-picker"'
    refute_includes body, 'colo-unavailable-notice',
                    'the gate is gone; leaving its markup behind invites re-gating by accident'
    refute_includes body, 'temporarily unavailable'
  end

  def test_colo_offers_only_genomes_that_have_colocalization_data
    # The tab strip comes from Analysis.genomes_with_colo, which is derived
    # from the data rather than an allowlist. The seed gives hg38 real cell
    # types and TAIR12 only "-", so TAIR12 must not be offered.
    seed_analyses
    get '/colo'

    genomes = JSON.parse(last_response.body[/<script id="page-data"[^>]*>(.*?)<\/script>/m, 1])['genomes']
    assert genomes.key?('hg38')
    refute genomes.key?('TAIR12')
  end

  def test_colo_result_has_legends_download_links_and_a_result_table
    get '/colo_result'
    body = last_response.body
    assert_includes body, 'id="result-summary"'
    assert_includes body, 'id="download-tsv"'
    assert_includes body, 'id="download-gml"'
    assert_includes body, 'class="tg-legend"'
    assert_includes body, 'id="loading-state"'
    assert_includes body, 'id="error-state"'
    assert_includes body, 'id="result-wrap"'
    assert_includes body, 'id="experiments-toggle"'
    assert_includes body, '<summary'
    assert_includes body, 'id="result-table-wrap"'
    assert_includes body, 'id="result-thead-row"'
    assert_includes body, 'id="result-tbody"'
    assert_includes body, 'id="row-count"'
  end

  def test_analysis_pages_have_a_tutorial_dropdown
    %w[/peak_browser /enrichment_analysis /diff_analysis /target_genes /colo /search].each do |path|
      get path
      assert_includes last_response.body, 'Tutorial', "#{path} has no Tutorial button"
      assert_includes last_response.body, 'chip-atlas.svg#question-circle'
    end
  end

  # --- the shared not_found handler (routes/pages.rb) ---
  #
  # Sinatra re-runs the registered `error 404`/`not_found` handler for ANY
  # response that ends at status 404 - including a route's own explicit
  # `halt 404, json_response(...)` - not only a genuine routing miss (see
  # Sinatra::Base#call!: `invoke { error_block!(response.status) }` runs
  # unconditionally unless an exception was raised). Left unguarded, that
  # meant the HTML `not_found.erb` page silently replaced the JSON body of
  # every `/api/*` 404, while keeping the already-set
  # `content-type: application/json` header - a client saw a JSON
  # content-type with an HTML payload. See task B2's report for how this
  # was found and its blast radius.

  def test_an_unmatched_page_path_still_gets_the_html_not_found_page
    get '/this_page_definitely_does_not_exist'
    assert_equal 404, last_response.status
    assert_includes last_response.body, 'ChIP-Atlas: 404'
    assert_includes last_response.content_type.to_s, 'text/html'
  end

  def test_an_unmatched_api_path_gets_a_json_not_found_body_not_html
    get '/api/this_endpoint_does_not_exist'
    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type.to_s.split(';').first
    data = JSON.parse(last_response.body)
    assert_equal 'Not found', data['error']
    refute_includes last_response.body, '<html', 'an unmatched /api/* path must not fall back to the HTML page'
  end

  # SHELL-25: these four agent-facing documents drifted to say the arabidopsis
  # assembly is "TAIR10" (config/genomes.yml and /api/genomes both say
  # TAIR12 - TAIR10 does not exist in this app at all), so an agent that
  # trusted the docs and requested genome=TAIR10 got an empty result or a
  # 400. /llms.txt and /openapi.yaml are static files under public/, served
  # by Sinatra's default static middleware rather than an explicit route,
  # but Rack::Test drives that the same as any other GET.
  TAIR10_FREE_DOCS = %w[/agents /demo /llms.txt /openapi.yaml].freeze

  def test_agent_docs_do_not_mention_the_nonexistent_tair10_assembly
    TAIR10_FREE_DOCS.each do |path|
      get path
      assert_equal 200, last_response.status, "#{path} did not return 200"
      refute_includes last_response.body, 'TAIR10', "#{path} still mentions TAIR10"
    end
  end

  # SHELL-27: these docs' colocalization example used cell_type=K-562, which
  # 404s - /api/colo's cell_type is keyed by cell-type *class* (as listed by
  # /api/colo_index), and K-562 is a subclass/cell line, not a class. Blood
  # is a real class and returns 200.
  def test_agent_docs_colo_example_uses_a_cell_type_class_not_a_cell_line
    %w[/agents /demo /llms.txt].each do |path|
      get path
      assert_includes last_response.body, 'cell_type=Blood', "#{path} is missing the corrected colo example"
      refute_includes last_response.body, 'cell_type=K-562', "#{path} still has the 404ing colo example"
    end
  end
end
