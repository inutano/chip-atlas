# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['DATABASE_URL'] = 'sqlite:/'

require 'minitest/autorun'
require 'rack/test'
require 'sequel'
require 'json'

DB = Sequel.connect(ENV['DATABASE_URL'])
Sequel.extension :migration
Sequel::Migrator.run(DB, File.join(__dir__, '..', 'db', 'migrations'))

require_relative '../lib/chip_atlas'

module TestHelper
  def seed_experiments
    DB[:experiments].multi_insert([
      { experiment_id: 'SRX018625', genome: 'hg38', track_class: 'Histone',
        track_subclass: 'H3K4me3', cell_type_class: 'Blood', cell_type_subclass: 'K-562',
        cell_type_subclass_info: '', read_info: '15000000,50', title: 'H3K4me3 in K-562',
        attributes: 'cell line', created_at: Time.now },
      { experiment_id: 'SRX018626', genome: 'hg38', track_class: 'TFs and others',
        track_subclass: 'CTCF', cell_type_class: 'Blood', cell_type_subclass: 'K-562',
        cell_type_subclass_info: '', read_info: '20000000,50', title: 'CTCF in K-562',
        attributes: 'cell line', created_at: Time.now },
      { experiment_id: 'SRX100001', genome: 'hg38', track_class: 'Histone',
        track_subclass: 'H3K27ac', cell_type_class: 'Brain', cell_type_subclass: 'Neuron',
        cell_type_subclass_info: '', read_info: '10000000,75', title: 'H3K27ac in Neuron',
        attributes: 'primary cell', created_at: Time.now },
      { experiment_id: 'SRX100002', genome: 'mm10', track_class: 'ATAC-Seq',
        track_subclass: '-', cell_type_class: 'Liver', cell_type_subclass: 'Hepatocyte',
        cell_type_subclass_info: '', read_info: '8000000,150', title: 'ATAC-seq in Hepatocyte',
        attributes: 'primary cell', created_at: Time.now },
    ])
  end

  def seed_bedfiles
    DB[:bedfiles].multi_insert([
      { filename: 'H3K4me3.Blood.05', genome: 'hg38', track_class: 'Histone',
        track_subclass: 'H3K4me3', cell_type_class: 'Blood', cell_type_subclass: '-',
        qval: '05', experiments: 'SRX018625', created_at: Time.now },
      { filename: 'H3K4me3.ALL.05', genome: 'hg38', track_class: 'Histone',
        track_subclass: 'H3K4me3', cell_type_class: 'All cell types', cell_type_subclass: '-',
        qval: '05', experiments: 'SRX018625,SRX100001', created_at: Time.now },
    ])
  end

  def seed_analyses
    DB[:analyses].multi_insert([
      { track: 'CTCF', cell_list: 'K-562,HeLa-S3,GM12878',
        target_genes: true, genome: 'hg38', created_at: Time.now },
      { track: 'H3K4me3', cell_list: 'K-562,Neuron',
        target_genes: false, genome: 'hg38', created_at: Time.now },
    ])
  end

  def seed_sra_cache
    DB[:sra_cache].multi_insert([
      { experiment_id: 'SRX018625',
        metadata_json: JSON.generate(
          experiment_id: 'SRX018625',
          library_description: {
            library_name: 'H3K4me3 ChIP-seq library',
            library_strategy: 'ChIP-Seq',
            library_source: 'GENOMIC',
            library_selection: 'ChIP',
            library_construction_protocol: 'Standard Illumina library construction protocol',
          },
          platform_information: {
            instrument_model: 'Illumina HiSeq 2000',
            cycle_sequence: '', cycle_count: '', flow_sequence: '', flow_count: '', key_sequence: '',
          },
          platform: 'ILLUMINA',
          library_layout: 'SINGLE',
          library_orientation: '',
          library_nominal_length: '',
          library_nominal_sdev: '',
        ),
        fetched_at: Time.now, created_at: Time.now },
    ])
  end

  def seed_bedsizes
    DB[:bedsizes].multi_insert([
      { genome: 'hg38', track_class: 'Histone', cell_type_class: 'Blood',
        qval: '05', number_of_lines: 150000, created_at: Time.now },
      { genome: 'hg38', track_class: 'Histone', cell_type_class: 'Brain',
        qval: '05', number_of_lines: 80000, created_at: Time.now },
    ])
  end

  def seed_all
    seed_experiments
    seed_bedfiles
    seed_analyses
    seed_bedsizes
  end

  def teardown
    DB[:experiments].delete
    DB[:bedfiles].delete
    DB[:bedsizes].delete
    DB[:analyses].delete
    DB[:sra_cache].delete
    DB.run("DELETE FROM experiments_fts")
    # ExperimentSearch.list_all memoizes total row counts in-process (see
    # lib/models/experiment_search.rb) to avoid a full-table COUNT(*) OVER()
    # scan on every /search page load. Tests insert into experiments_fts
    # directly (bypassing ChipAtlas::Experiment.load_from_files, which is
    # what resets that cache after a normal load), so reset it here to
    # keep tests isolated.
    ChipAtlas::ExperimentSearch.reset_total_count_cache!
  end
end
