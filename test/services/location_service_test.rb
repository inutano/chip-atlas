# frozen_string_literal: true

require_relative '../test_helper'

class LocationServiceTest < Minitest::Test
  include TestHelper

  def setup
    seed_bedfiles
    # Stub the network HEAD probe so extension resolution never touches the
    # real archive in tests. Default: only bare `.bed` URLs are "live",
    # matching hg38's current state on the data server.
    ChipAtlas::BedExtensionResolver.prober = ->(url) { url.end_with?('.bed') }
  end

  def teardown
    ChipAtlas::BedExtensionResolver.prober = nil
    super
  end

  def test_archive_url
    data = { 'condition' => {
      'genome' => 'hg38', 'track_class' => 'Histone', 'track_subclass' => 'H3K4me3',
      'cell_type_class' => 'Blood', 'cell_type_subclass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/assembled/H3K4me3.Blood.05.bed', svc.archive_url
  end

  def test_archive_url_falls_back_to_bed_gz_for_tair12
    DB[:bedfiles].insert(
      filename: 'His.ALL.05.H3K4me3.AllCell', genome: 'TAIR12', track_class: 'Histone',
      track_subclass: 'H3K4me3', cell_type_class: 'All cell types', cell_type_subclass: '-',
      qval: '05', experiments: 'SRX000001', created_at: Time.now
    )
    # TAIR12 only serves the gzipped form right now.
    ChipAtlas::BedExtensionResolver.prober = ->(url) { url.end_with?('.bed.gz') }

    data = { 'condition' => {
      'genome' => 'TAIR12', 'track_class' => 'Histone', 'track_subclass' => 'H3K4me3',
      'cell_type_class' => 'All cell types', 'cell_type_subclass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_equal 'https://chip-atlas.dbcls.jp/data/TAIR12/assembled/His.ALL.05.H3K4me3.AllCell.bed.gz',
                 svc.archive_url
  end

  def test_igv_browsing_url
    data = { 'condition' => {
      'genome' => 'hg38', 'track_class' => 'Histone', 'track_subclass' => 'H3K4me3',
      'cell_type_class' => 'Blood', 'cell_type_subclass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_match %r{http://localhost:60151/load\?genome=hg38}, svc.igv_browsing_url
  end

  def test_colo_urls
    data = { 'condition' => {
      'genome' => 'hg38', 'track' => 'CTCF', 'cell_type' => 'K-562'
    }}
    svc = ChipAtlas::LocationService.new(data)

    assert_match %r{/hg38/colo/CTCF\.K-562\.tsv$}, svc.colo_tsv_url
    assert_match %r{/hg38/colo/K-562\.gml$}, svc.colo_gml_url
  end

  def test_target_genes_urls
    data = { 'condition' => {
      'genome' => 'hg38', 'track' => 'CTCF', 'distance' => '5000'
    }}
    svc = ChipAtlas::LocationService.new(data)

    assert_match %r{/hg38/target/CTCF\.5000\.tsv$}, svc.target_genes_tsv_url
  end

  def test_archive_url_returns_nil_for_missing_bedfile
    data = { 'condition' => {
      'genome' => 'hg38', 'track_class' => 'Histone', 'track_subclass' => 'NONEXISTENT',
      'cell_type_class' => 'Blood', 'cell_type_subclass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_nil svc.archive_url
  end

  def test_distribution_png_url
    svc = ChipAtlas::LocationService.new(
      'condition' => { 'genome' => 'hg38', 'experiment_id' => 'SRX019491' }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/distribution/png/SRX019491.dist.png',
                 svc.distribution_png_url
  end

  def test_correlation_png_url
    svc = ChipAtlas::LocationService.new(
      'condition' => { 'genome' => 'hg38', 'experiment_id' => 'SRX019491' }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/correlation/png/SRX019491.cor.png',
                 svc.correlation_png_url
  end

  def test_correlation_tsv_url_underscores_spaces
    svc = ChipAtlas::LocationService.new(
      'condition' => {
        'genome' => 'hg38',
        'track_subclass' => 'Input control',
        'cell_type_subclass' => 'Adipose stromal cell'
      }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/correlation/tsv/' \
                 'hg38__x__Input_control__x__Adipose_stromal_cell.tsv',
                 svc.correlation_tsv_url
  end
end
