# frozen_string_literal: true

require_relative '../test_helper'

class LocationServiceTest < Minitest::Test
  include TestHelper

  def setup
    seed_bedfiles
  end

  def test_archive_url
    data = { 'condition' => {
      'genome' => 'hg38', 'ag_class' => 'Histone', 'ag_sub_class' => 'H3K4me3',
      'cl_class' => 'Blood', 'cl_sub_class' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    url = svc.archive_url

    assert_match %r{https://chip-atlas\.dbcls\.jp/data/hg38/assembled/H3K4me3\.Blood\.05\.bed}, url
  end

  def test_igv_browsing_url
    data = { 'condition' => {
      'genome' => 'hg38', 'ag_class' => 'Histone', 'ag_sub_class' => 'H3K4me3',
      'cl_class' => 'Blood', 'cl_sub_class' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    url = svc.igv_browsing_url

    assert_match %r{http://localhost:60151/load\?genome=hg38}, url
  end

  def test_colo_url
    data = { 'condition' => {
      'genome' => 'hg38', 'antigen' => 'CTCF', 'cellline' => 'K-562'
    }}
    svc = ChipAtlas::LocationService.new(data)

    assert_match %r{/hg38/colo/CTCF\.K-562\.html}, svc.colo_url('submit')
    assert_match %r{/hg38/colo/CTCF\.K-562\.tsv}, svc.colo_url('tsv')
    assert_match %r{/hg38/colo/K-562\.gml}, svc.colo_url('gml')
  end

  def test_target_genes_url
    data = { 'condition' => {
      'genome' => 'hg38', 'antigen' => 'CTCF', 'distance' => '5000'
    }}
    svc = ChipAtlas::LocationService.new(data)

    assert_match %r{/hg38/target/CTCF\.5000\.html}, svc.target_genes_url('submit')
    assert_match %r{/hg38/target/CTCF\.5000\.tsv}, svc.target_genes_url('tsv')
  end

  def test_archive_url_returns_nil_for_missing_bedfile
    data = { 'condition' => {
      'genome' => 'hg38', 'ag_class' => 'Histone', 'ag_sub_class' => 'NONEXISTENT',
      'cl_class' => 'Blood', 'cl_sub_class' => '-', 'qval' => '05'
    }}
    svc = ChipAtlas::LocationService.new(data)
    assert_nil svc.archive_url
  end
end
