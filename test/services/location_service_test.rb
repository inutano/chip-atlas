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
    assert_match %r{genome=https://chip-atlas\.dbcls\.jp/data/genome/hg38/hg38\.json}, svc.igv_browsing_url
  end

  # The owner's report: IGV desktop has no bundled TAIR12 genome, so handing
  # it the bare code (genome=TAIR12) leaves the load silently unresolved.
  # Every assembly's genome= value must instead be the genome's own JSON URL
  # (https://chip-atlas.dbcls.jp/data/genome/<g>/<g>.json), which is also
  # that JSON's own `id` field -- see SCRATCH/investigation/igv.md.
  def test_igv_browsing_url_for_tair12_uses_the_genome_json_url
    DB[:bedfiles].insert(
      filename: 'His.ALL.05.H3K4me3.AllCell', genome: 'TAIR12', track_class: 'Histone',
      track_subclass: 'H3K4me3', cell_type_class: 'All cell types', cell_type_subclass: '-',
      qval: '05', experiments: 'SRX000001', created_at: Time.now
    )
    ChipAtlas::BedExtensionResolver.prober = ->(url) { url.end_with?('.bed.gz') }

    data = { 'condition' => {
      'genome' => 'TAIR12', 'track_class' => 'Histone', 'track_subclass' => 'H3K4me3',
      'cell_type_class' => 'All cell types', 'cell_type_subclass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_match %r{genome=https://chip-atlas\.dbcls\.jp/data/genome/TAIR12/TAIR12\.json},
                 svc.igv_browsing_url
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

  # SV-41: production sanitises with gsub(/[^a-zA-Z0-9_-]/, '_'), not just
  # spaces -- a plain tr(' ', '_') leaves '+', '.', '/', ',' etc. in the
  # URL and 404s against the data server for ~5.8% of antigen/cell-type
  # names (old-app/views/experiment.haml:333-338).
  def test_correlation_tsv_url_sanitises_special_characters_like_production
    svc = ChipAtlas::LocationService.new(
      'condition' => {
        'genome' => 'hg38',
        'track_subclass' => 'H2A.Z',
        'cell_type_subclass' => 'CD4+ T cells'
      }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/hg38/correlation/tsv/' \
                 'hg38__x__H2A_Z__x__CD4__T_cells.tsv',
                 svc.correlation_tsv_url
  end

  def test_correlation_tsv_url_sanitises_slash_in_cell_type_name
    svc = ChipAtlas::LocationService.new(
      'condition' => {
        'genome' => 'mm10',
        'track_subclass' => 'CTCF',
        'cell_type_subclass' => 'NIH/3T3'
      }
    )
    assert_equal 'https://chip-atlas.dbcls.jp/data/mm10/correlation/tsv/' \
                 'mm10__x__CTCF__x__NIH_3T3.tsv',
                 svc.correlation_tsv_url
  end

  # PB-19: igv_browsing_url used to look up the trackname with the caller's
  # raw cell_type_class (e.g. "NA") while the filename lookup silently
  # overrode it to "All cell types" -- so a request that worked for
  # download_url raised Bedfile::NotFound, uncaught, for igv_url. Both
  # lookups must use the same merged condition.
  def test_igv_browsing_url_for_annotation_tracks_overrides_cell_type_class_to_all_cell_types
    DB[:bedfiles].insert(
      filename: 'cpg_island.hg38.bed', genome: 'hg38', track_class: 'Annotation tracks',
      track_subclass: 'CpG Islands', cell_type_class: 'All cell types', cell_type_subclass: '-',
      qval: 'anno', experiments: '', created_at: Time.now
    )
    data = { 'condition' => {
      'genome' => 'hg38', 'track_class' => 'Annotation tracks', 'track_subclass' => 'CpG Islands',
      'cell_type_class' => 'NA', 'cell_type_subclass' => '-', 'qval' => 'anno'
    }}
    svc = ChipAtlas::LocationService.new(data)
    url = svc.igv_browsing_url
    assert_match %r{genome=https://chip-atlas\.dbcls\.jp/data/genome/hg38/hg38\.json}, url
    assert_match %r{file=https://chip-atlas\.dbcls\.jp/data/annotations/hg38/cpg_island\.hg38\.bed}, url
    assert_match(/name=CpG Islands/, url)
  end

  def test_igv_browsing_url_for_annotation_tracks_returns_nil_instead_of_raising_when_no_bedfile_matches
    data = { 'condition' => {
      'genome' => 'hg38', 'track_class' => 'Annotation tracks', 'track_subclass' => 'NoSuchSubclass',
      'cell_type_class' => 'NA', 'cell_type_subclass' => '-', 'qval' => 'anno'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_nil svc.igv_browsing_url
  end

  # Finding 1 (2026-09-24 final review): the non-Annotation `else` branch
  # used to interpolate bed_url directly into the URL string. bed_url
  # rescues Bedfile::NotFound internally and returns nil on no match, so the
  # interpolation produced "http://localhost:60151/load?genome=hg38&file="
  # (an empty file= param) instead of igv_browsing_url returning nil -- the
  # same contract archive_url/download_url already have for a no-match.
  def test_igv_browsing_url_returns_nil_instead_of_empty_file_param_when_no_bedfile_matches
    data = { 'condition' => {
      'genome' => 'hg38', 'track_class' => 'Histone', 'track_subclass' => 'NONEXISTENT',
      'cell_type_class' => 'Blood', 'cell_type_subclass' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_nil svc.igv_browsing_url
  end
end
