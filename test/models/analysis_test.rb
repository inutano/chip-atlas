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

  def test_load_from_file_splits_track_and_distance
    DB[:analyses].delete
    fixture = File.join(__dir__, '..', 'fixtures', 'analysis_list_sample.tab')

    count = ChipAtlas::Analysis.load_from_file(fixture)

    # Ahr.1/ce10 is dropped: ce10 is not in config/genomes.yml.
    assert_equal 4, count

    tair12 = DB[:analyses].where(genome: 'TAIR12').first
    assert_equal 'AGL20', tair12[:track]
    assert_equal '1', tair12[:distance]

    mm10 = DB[:analyses].where(genome: 'mm10').first
    assert_equal 'Acaa2', mm10[:track]
    assert_equal '10', mm10[:distance]

    # "wdr-5.1.1" / "wdr-5.1.5": the antigen name itself contains a dot
    # ("wdr-5.1"), so only the LAST dot-separated segment is the distance -
    # a naive split('.') would corrupt this into track "wdr-5" + distance
    # "1.1".
    ce11 = DB[:analyses].where(genome: 'ce11').order(:distance).all
    assert_equal %w[wdr-5.1 wdr-5.1], ce11.map { |row| row[:track] }
    assert_equal %w[1 5], ce11.map { |row| row[:distance] }

    refute DB[:analyses].where(genome: 'ce10').any?, 'ce10 is not in config/genomes.yml and must be dropped'
  end

  def test_split_track_and_distance_handles_dotted_antigen_names
    assert_equal %w[Acaa2 10], ChipAtlas::Analysis.split_track_and_distance('Acaa2.10')
    assert_equal ['wdr-5.1', '1'], ChipAtlas::Analysis.split_track_and_distance('wdr-5.1.1')
    assert_equal ['wdr-5.1', '10'], ChipAtlas::Analysis.split_track_and_distance('wdr-5.1.10')
  end

  def test_target_genes_result_falls_back_to_human_snapshot_for_genomes_the_tab_does_not_cover
    fixture = File.join(__dir__, '..', 'fixtures', 'target_genes_human_snapshot_sample.json')
    ChipAtlas::Analysis.human_snapshot_path = fixture

    result = ChipAtlas::Analysis.target_genes_result

    # rn6 has no rows in the seeded analyses table at all, so it falls back
    # to the snapshot.
    assert_equal %w[Ahr Ar], result['rn6']

    # hg38 DOES have rows (seeded above), so the real DB data wins over
    # whatever the snapshot says - the fallback is only for genomes the tab
    # has zero rows for.
    assert_includes result['hg38'], 'CTCF'

    # hg19 is in the snapshot but not in config/genomes.yml (a legacy build
    # this app deliberately does not support) and must not leak in.
    refute result.key?('hg19')
  ensure
    ChipAtlas::Analysis.reset_human_snapshot_path!
  end

  def test_genomes_with_colo_excludes_tair12
    genomes = ChipAtlas::Analysis.genomes_with_colo

    assert genomes.key?('hg38')
    refute genomes.key?('TAIR12'), 'TAIR12 has no colo/ directory on the archive and must not offer Colo'
    assert_equal 'A. thaliana (TAIR12)', ChipAtlas::Experiment.genomes['TAIR12'],
                 'sanity check: TAIR12 is still in the full genome registry, just not in the colo one'
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
