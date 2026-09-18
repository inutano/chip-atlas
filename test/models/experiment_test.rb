# frozen_string_literal: true

require_relative '../test_helper'
require 'tempfile'
require 'set'

class ExperimentTest < Minitest::Test
  include TestHelper

  def setup
    seed_experiments
  end

  def test_list_of_genome
    genomes = ChipAtlas::Experiment.list_of_genome
    assert_includes genomes.keys, 'hg38'
    assert_includes genomes.keys, 'mm10'
    assert_includes genomes.keys, 'TAIR12'
    assert_equal 'H. sapiens (hg38)', genomes['hg38']
  end

  # Proves the registry is config-driven: ids, labels, and their order come
  # from whatever YAML file genomes_config_path points at, not from a Ruby
  # constant. Points the registry at a fixture with a different id set and
  # order than config/genomes.yml and checks the result changes to match.
  def test_genome_registry_is_config_driven
    ChipAtlas::Experiment.genomes_config_path =
      File.join(__dir__, '..', 'fixtures', 'genomes_sample.yml')

    assert_equal %w[zz99 aa11 mm00], ChipAtlas::Experiment.genomes.keys
    assert_equal 'Z. zzyzxus (zz99)', ChipAtlas::Experiment.genomes['zz99']
    assert_equal({ 'zz99' => 0, 'aa11' => 1, 'mm00' => 2 }, ChipAtlas::Experiment.genome_order)
    refute_includes ChipAtlas::Experiment.genomes.keys, 'hg38'
  ensure
    ChipAtlas::Experiment.reset_genomes_config_path!
  end

  def test_list_of_experiment_types
    types = ChipAtlas::Experiment.list_of_experiment_types
    assert types.any? { |t| t[:id] == 'Histone' }
    assert types.any? { |t| t[:id] == 'CUT&Tag' }
    assert types.any? { |t| t[:id] == 'CUT&RUN' }
  end

  def test_experiment_types_with_counts
    result = ChipAtlas::Experiment.experiment_types('hg38', 'All cell types')
    histone = result.find { |r| r[:id] == 'Histone' }
    assert_equal 2, histone[:count]
  end

  def test_experiment_types_filtered_by_cell_class
    result = ChipAtlas::Experiment.experiment_types('hg38', 'Blood')
    histone = result.find { |r| r[:id] == 'Histone' }
    assert_equal 1, histone[:count]
  end

  def test_sample_types
    result = ChipAtlas::Experiment.sample_types('hg38', 'Histone')
    assert_equal 'All cell types', result.first[:id]
    assert_equal 2, result.first[:count]
    blood = result.find { |r| r[:id] == 'Blood' }
    assert_equal 1, blood[:count]
  end

  def test_chip_antigen
    result = ChipAtlas::Experiment.chip_antigen('hg38', 'Histone', 'All cell types')
    assert_equal '-', result.first[:id]
    h3k4 = result.find { |r| r[:id] == 'H3K4me3' }
    assert_equal 1, h3k4[:count]
  end

  def test_cell_type
    result = ChipAtlas::Experiment.cell_type('hg38', 'Histone', 'Blood')
    assert_equal '-', result.first[:id]
    k562 = result.find { |r| r[:id] == 'K-562' }
    assert_equal 1, k562[:count]
  end

  def test_cell_type_returns_only_all_when_no_class
    result = ChipAtlas::Experiment.cell_type('hg38', 'Histone', 'All cell types')
    assert_equal 1, result.size
    assert_equal '-', result.first[:id]
  end

  def test_record_by_experiment_id
    records = ChipAtlas::Experiment.record_by_experiment_id('SRX018625')
    assert_equal 1, records.size
    assert_equal 'SRX018625', records.first[:experiment_id]
    assert_equal 'Histone', records.first[:track_class]
  end

  def test_id_valid
    assert ChipAtlas::Experiment.id_valid?('SRX018625')
    refute ChipAtlas::Experiment.id_valid?('NONEXISTENT')
  end

  def test_number_of_experiments
    count = ChipAtlas::Experiment.number_of_experiments
    assert_equal 4, count
  end

  def test_total_number_of_reads
    total = ChipAtlas::Experiment.total_number_of_reads(['SRX018625', 'SRX018626'])
    assert_equal 35000000, total
  end

  def test_index_all_genome
    index = ChipAtlas::Experiment.index_all_genome
    assert index.key?('hg38')
    assert index['hg38'].key?(:track)
    assert index['hg38'].key?(:cell_type)
    assert index['hg38'][:track].key?('Histone')
  end

  # --- load_from_files: one reconciled row set feeding both stores ---
  #
  # Fixtures:
  #   test/fixtures/experimentList_sample.tab (experimentList.tab shape):
  #     SRXTEST001  hg38  Histone             - confirmed by the JSON fixture
  #     SRXTEST002  hg38  Annotation tracks    - not in the JSON fixture at all
  #     SRXTEST003  mm10  ATAC-Seq             - confirmed by the JSON fixture
  #     SRXTEST004  xx99  Histone              - xx99 isn't in config/genomes.yml
  #     SRXTEST005  hg38  Histone              - IS in the JSON fixture, but the
  #                                              JSON claims dm6, not hg38, for it
  #   test/fixtures/experiment_adv_sample.json (ExperimentList_adv.json shape):
  #     SRXTEST001  genome "hg38"        sra_id/geo_id populated
  #     SRXTEST003  genome "mm10, mm9"   comma-joined; mm9 isn't supported
  #     SRXTEST005  genome "dm6"         doesn't match the tab row's hg38
  #     SRXTEST999  genome "hg38"        not in the tab fixture at all

  def load_reconciled_fixtures
    tab = File.join(__dir__, '..', 'fixtures', 'experimentList_sample.tab')
    json = File.join(__dir__, '..', 'fixtures', 'experiment_adv_sample.json')
    ChipAtlas::Experiment.load_from_files(tab, json)
  end

  def test_load_from_files_builds_experiments_from_tab_and_search_index_from_json
    DB[:experiments].delete
    DB[:experiments_fts].delete

    stats = load_reconciled_fixtures

    # experiments = every tab row that passes the genome filter, full stop -
    # xx99 (SRXTEST004) is the only one dropped; JSON confirmation is NOT
    # required for a row to exist in experiments.
    assert_equal 4, stats[:experiments]
    assert_equal 4, DB[:experiments].count
    refute ChipAtlas::Experiment.id_valid?('SRXTEST004')
    assert ChipAtlas::Experiment.id_valid?('SRXTEST002') # Annotation tracks: still viewable
    assert ChipAtlas::Experiment.id_valid?('SRXTEST005') # unconfirmed by JSON: still viewable

    # experiments_fts = only the pairs BOTH sources agree on, minus
    # Annotation tracks: SRXTEST001 (hg38) and SRXTEST003 (mm10).
    assert_equal 2, stats[:indexed]
    assert_equal 2, DB[:experiments_fts].count
    assert DB[:experiments_fts].where(experiment_id: 'SRXTEST001').first
    assert DB[:experiments_fts].where(experiment_id: 'SRXTEST003').first
    refute DB[:experiments_fts].where(experiment_id: 'SRXTEST002').first # Annotation tracks
    refute DB[:experiments_fts].where(experiment_id: 'SRXTEST005').first # genome mismatch

    # The structural guarantee this task is about: every experiments_fts
    # row has a matching experiments row.
    assert_equal 0, ChipAtlas::ExperimentSearch.orphaned_count
  end

  def test_load_from_files_reports_both_directions_of_drift
    DB[:experiments].delete
    DB[:experiments_fts].delete

    stats = load_reconciled_fixtures

    # tab_only: in experiments, excluded from the index - SRXTEST002 (no
    # JSON row at all) and SRXTEST005 (JSON row exists but claims a
    # different genome). Proves the exclusion isn't only about Annotation
    # tracks - an ordinary track_class with an unconfirmed genome is
    # excluded too.
    assert_equal 2, stats[:tab_only]

    # json_only: JSON (experiment_id, genome) pairs the tab file never
    # backs up, dropped from both stores entirely rather than silently
    # trusted - SRXTEST999/hg38 (id not in the tab fixture) and
    # SRXTEST005/dm6 (the other side of the tab_only mismatch above).
    assert_equal 2, stats[:json_only]
    refute ChipAtlas::Experiment.id_valid?('SRXTEST999')
  end

  def test_load_from_files_gives_experiments_fts_real_sra_id_and_geo_id
    DB[:experiments].delete
    DB[:experiments_fts].delete
    load_reconciled_fixtures

    # experiments_fts carries the JSON's real sra_id/geo_id (dropped the
    # GSM-prefix-from-title heuristic entirely - the JSON has the actual
    # column). This is the whole point of joining the JSON in at all:
    # nothing reads experiments.sra_id/geo_id (no route selects them, and
    # ExperimentSearch.gsm_to_srx reads experiments_fts' copy), so the
    # join's only output is here, not duplicated onto `experiments`.
    fts_row = DB[:experiments_fts].where(experiment_id: 'SRXTEST001').first
    assert_equal 'SRA100001', fts_row[:sra_id]
    assert_equal 'GSM100001', fts_row[:geo_id]

    # The JSON's own placeholder ("-" for a genuinely missing geo_id) is
    # passed through as-is, not fabricated or blanked.
    placeholder = DB[:experiments_fts].where(experiment_id: 'SRXTEST003').first
    assert_equal 'SRA100003', placeholder[:sra_id]
    assert_equal '-', placeholder[:geo_id]

    # experiments itself does not carry sra_id/geo_id at all.
    refute_includes DB[:experiments].columns, :sra_id
    refute_includes DB[:experiments].columns, :geo_id
  end

  def test_load_json_index_handles_comma_joined_genome_field
    json = File.join(__dir__, '..', 'fixtures', 'experiment_adv_sample.json')
    index = ChipAtlas::Experiment.load_json_index(json)

    # "mm10, mm9" - split, trimmed, and filtered through config/genomes.yml
    # (mm9 isn't in it). Matching the raw comma-joined string against the
    # registry instead of splitting it first is the exact bug that used to
    # drop ~95% of the index - this proves the unified loader still splits.
    assert_equal Set['mm10'], index['SRXTEST003'][:genomes]
    assert_equal Set['hg38'], index['SRXTEST001'][:genomes]
  end

  # Isolated from the shared fixtures above on purpose: those exercise a
  # tab_only row that is NOT an Annotation track (the genome-mismatch case),
  # which is exactly what makes "totals differ by the annotation-track
  # count" not hold in general - see task-A3-report.md for why, on the real
  # production snapshot, every tab_only row IS an Annotation track and the
  # two counts do coincide there. This test builds a minimal pair where
  # that's true by construction, to assert the relationship the brief asks
  # for cleanly instead of muddying it with the mismatch scenario above.
  def test_experiments_and_search_totals_differ_by_annotation_track_count
    DB[:experiments].delete
    DB[:experiments_fts].delete

    tab = Tempfile.new('experimentList')
    tab.write([
      "SRXA\thg38\tHistone\tH3K4me3\tBlood\tK-562\tNA\t1,1\tHistone row\tk=v\n",
      "SRXB\thg38\tAnnotation tracks\tAnnotation tracks\t-\t-\tNA\t-\tAnnotation row\tk=v\n",
    ].join)
    tab.close

    json = Tempfile.new(['ExperimentList_adv', '.json'])
    json.write(JSON.generate({
      'data' => [
        ['SRXA', 'SRA1', 'GSM1', 'hg38', 'Histone', 'H3K4me3', 'Blood', 'K-562', 'Histone row', 'k=v'],
        # SRXB (the Annotation track) deliberately has no JSON row - matches
        # production, where Annotation-tracks ids never appear in the JSON.
      ],
    }))
    json.close

    ChipAtlas::Experiment.load_from_files(tab.path, json.path)

    annotation_track_count = DB[:experiments].where(track_class: 'Annotation tracks').count
    assert_equal 1, annotation_track_count

    total_experiments = ChipAtlas::Experiment.number_of_experiments
    search_total = ChipAtlas::ExperimentSearch.total_count
    assert_equal total_experiments - annotation_track_count, search_total
  ensure
    tab&.unlink
    json&.unlink
  end
end
