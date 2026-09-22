# frozen_string_literal: true

require_relative '../test_helper'

class AnalysisTest < Minitest::Test
  include TestHelper

  def setup
    seed_analyses
  end

  def test_colo_result_by_genome
    result = ChipAtlas::Analysis.colo_result_by_genome('hg38')

    assert result.key?('hg38')
    track_index = result['hg38'][:track]
    cell_type_index = result['hg38'][:cell_type]

    # Track -> cell_types mapping
    assert_equal %w[K-562 HeLa-S3 GM12878], track_index['CTCF']
    assert_equal %w[K-562 Neuron], track_index['H3K4me3']

    # Cell_type -> tracks mapping
    assert_includes cell_type_index['K-562'], 'CTCF'
    assert_includes cell_type_index['K-562'], 'H3K4me3'
    assert_includes cell_type_index['HeLa-S3'], 'CTCF'
    assert_includes cell_type_index['GM12878'], 'CTCF'
    assert_includes cell_type_index['Neuron'], 'H3K4me3'
  end

  def test_colo_result_by_genome_empty
    result = ChipAtlas::Analysis.colo_result_by_genome('dm6')

    assert result.key?('dm6')
    assert_empty result['dm6'][:track]
    assert_empty result['dm6'][:cell_type]
  end

  def test_target_genes_result
    result = ChipAtlas::Analysis.target_genes_result

    assert result.key?('hg38')
    assert_includes result['hg38'], 'CTCF'
    refute_includes result['hg38'], 'H3K4me3'
  end

  def test_load_from_file_stores_one_row_per_antigen_verbatim
    DB[:analyses].delete
    fixture = File.join(__dir__, '..', 'fixtures', 'analysis_list_sample.tab')

    stats = ChipAtlas::Analysis.load_from_file(fixture)

    # Ahr/ce10 is dropped: ce10 is not in config/genomes.yml. The other four
    # fixture rows are all for supported genomes.
    assert_equal 4, stats[:total]
    refute DB[:analyses].where(genome: 'ce10').any?, 'ce10 is not in config/genomes.yml and must be dropped'

    # The antigen name is stored exactly as the file spells it -- it is used
    # verbatim to build <genome>/target/<antigen>.<distance>.tsv, so any
    # transformation here breaks the lookup.
    assert_equal 'AGL20', DB[:analyses].where(genome: 'TAIR12').first[:track]
    assert_equal 'Acaa2', DB[:analyses].where(genome: 'mm10', track: 'Acaa2').first[:track]
    assert_equal 'wdr-5', DB[:analyses].where(genome: 'ce11').first[:track]

    assert_equal 'Liver,Neural', DB[:analyses].where(track: 'Acaa2').first[:cell_list]
    assert_equal false, DB[:analyses].where(track: 'NoTargetGenes').first[:target_genes]
  end

  def test_load_from_file_reports_zero_broken_build_rows_for_a_well_formed_file
    DB[:analyses].delete
    fixture = File.join(__dir__, '..', 'fixtures', 'analysis_list_sample.tab')

    assert_equal 0, ChipAtlas::Analysis.load_from_file(fixture)[:broken_build_rows]
  end

  def test_load_from_file_counts_the_broken_2026_09_build_signature
    # The 2026-09 build of analysisList.tab appended ".1"/".5"/".10" to every
    # antigen name, and this app ingested 8,345 such rows without a word --
    # which is what let a month of work be built on the wrong shape. The
    # count exists so that build announces itself; the rows are still stored
    # verbatim either way.
    DB[:analyses].delete
    fixture = File.join(__dir__, '..', 'fixtures', 'analysis_list_broken_build.tab')

    stats = ChipAtlas::Analysis.load_from_file(fixture)

    assert_equal 4, stats[:total], 'suspect rows are still stored, not skipped'
    assert_equal 3, stats[:broken_build_rows]
    assert_equal 'AGL20.1', DB[:analyses].where(genome: 'TAIR12').order(:track).first[:track]
    refute_nil DB[:analyses].where(track: 'Plain').first, 'the unsuffixed row is not counted'
  end

  def test_target_genes_result_covers_every_genome_from_the_flag_column_alone
    DB[:analyses].delete
    fixture = File.join(__dir__, '..', 'fixtures', 'analysis_list_sample.tab')
    ChipAtlas::Analysis.load_from_file(fixture)

    result = ChipAtlas::Analysis.target_genes_result

    assert_equal ['Acaa2'], result['mm10'], 'the "-" row must not be offered'
    # TAIR12 is the case the deleted vendored snapshot never covered: the
    # flag column answers for it like any other genome.
    assert_equal ['AGL20'], result['TAIR12']
    assert_equal ['wdr-5'], result['ce11']
  end

  def test_target_genes_result_does_not_invent_rows_for_genomes_with_none
    DB[:analyses].delete
    fixture = File.join(__dir__, '..', 'fixtures', 'analysis_list_sample.tab')
    ChipAtlas::Analysis.load_from_file(fixture)

    # rn6 has no rows. It used to be backfilled from a vendored snapshot of
    # production's index; that snapshot existed only to paper over the
    # broken build's missing human rows and is gone.
    refute ChipAtlas::Analysis.target_genes_result.key?('rn6')
  end

  # --- the "-" marker: 567 rows carry it in the real file ---

  def test_colo_result_by_genome_treats_a_dash_cell_list_as_no_colo_data
    result = ChipAtlas::Analysis.colo_result_by_genome('hg38')

    refute result['hg38'][:track].key?('NOCOLO'),
           'an antigen with no colo cell types must not be offered'
    refute result['hg38'][:cell_type].key?('-'),
           '"-".split(",") is ["-"], which is how a literal "-" became a cell-type class'
  end

  def test_colo_result_by_genome_offers_no_dash_in_either_direction
    result = ChipAtlas::Analysis.colo_result_by_genome('hg38')

    refute_includes result['hg38'][:cell_type].keys, '-'
    result['hg38'][:track].each_value do |cells|
      refute_includes cells, '-', 'a "-" must never appear inside a cell-type list either'
    end
  end

  # genomes_with_colo is derived from the data now, not an allowlist: the
  # seed gives hg38 rows with real cell types and TAIR12 rows that are all
  # "-", which is exactly the shape of the real file.
  def test_genomes_with_colo_excludes_a_genome_whose_rows_are_all_dashes
    genomes = ChipAtlas::Analysis.genomes_with_colo

    assert genomes.key?('hg38')
    refute genomes.key?('TAIR12'),
           'TAIR12 has rows but every cell_list is "-", so it has no colo data to offer'
    assert_equal 'A. thaliana (TAIR12)', ChipAtlas::Experiment.genomes['TAIR12'],
                 'sanity check: TAIR12 is still in the full genome registry, just not in the colo one'
  end

  def test_genomes_with_colo_excludes_a_genome_with_no_rows_at_all
    refute ChipAtlas::Analysis.genomes_with_colo.key?('rn6')
  end

  def test_genomes_with_colo_preserves_the_registry_order
    DB[:analyses].delete
    # Inserted back-to-front on purpose: the tab strip's order comes from
    # config/genomes.yml, never from whatever the query happens to return.
    DB[:analyses].multi_insert([
      { track: 'A', cell_list: 'Blood', target_genes: true, genome: 'sacCer3', created_at: Time.now },
      { track: 'B', cell_list: 'Blood', target_genes: true, genome: 'hg38', created_at: Time.now },
      { track: 'C', cell_list: 'Blood', target_genes: true, genome: 'mm10', created_at: Time.now },
    ])

    assert_equal %w[hg38 mm10 sacCer3], ChipAtlas::Analysis.genomes_with_colo.keys
  end

  def test_target_genes_distances
    distances = ChipAtlas::Analysis.target_genes_distances

    assert_equal 3, distances.size
    distances.each do |item|
      assert item.key?(:id), "Expected key :id in distance option"
      assert item.key?(:label), "Expected key :label in distance option"
    end
    assert_equal '1', distances.first[:id]
    assert_equal '10 kb', distances.last[:label]
  end
end
