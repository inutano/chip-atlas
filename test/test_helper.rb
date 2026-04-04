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
      { exp_id: 'SRX018625', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K4me3', cl_class: 'Blood', cl_sub_class: 'K-562',
        cl_sub_class_info: '', read_info: '15000000,50', title: 'H3K4me3 in K-562',
        attributes: 'cell line', created_at: Time.now },
      { exp_id: 'SRX018626', genome: 'hg38', ag_class: 'TFs and others',
        ag_sub_class: 'CTCF', cl_class: 'Blood', cl_sub_class: 'K-562',
        cl_sub_class_info: '', read_info: '20000000,50', title: 'CTCF in K-562',
        attributes: 'cell line', created_at: Time.now },
      { exp_id: 'SRX100001', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K27ac', cl_class: 'Brain', cl_sub_class: 'Neuron',
        cl_sub_class_info: '', read_info: '10000000,75', title: 'H3K27ac in Neuron',
        attributes: 'primary cell', created_at: Time.now },
      { exp_id: 'SRX100002', genome: 'mm10', ag_class: 'ATAC-Seq',
        ag_sub_class: '-', cl_class: 'Liver', cl_sub_class: 'Hepatocyte',
        cl_sub_class_info: '', read_info: '8000000,150', title: 'ATAC-seq in Hepatocyte',
        attributes: 'primary cell', created_at: Time.now },
    ])
  end

  def seed_bedfiles
    DB[:bedfiles].multi_insert([
      { filename: 'H3K4me3.Blood.05', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K4me3', cl_class: 'Blood', cl_sub_class: '-',
        qval: '05', experiments: 'SRX018625', created_at: Time.now },
      { filename: 'H3K4me3.ALL.05', genome: 'hg38', ag_class: 'Histone',
        ag_sub_class: 'H3K4me3', cl_class: 'All cell types', cl_sub_class: '-',
        qval: '05', experiments: 'SRX018625,SRX100001', created_at: Time.now },
    ])
  end

  def seed_analyses
    DB[:analyses].multi_insert([
      { antigen: 'CTCF', cell_list: 'K-562,HeLa-S3,GM12878',
        target_genes: true, genome: 'hg38', created_at: Time.now },
      { antigen: 'H3K4me3', cell_list: 'K-562,Neuron',
        target_genes: false, genome: 'hg38', created_at: Time.now },
    ])
  end

  def seed_bedsizes
    DB[:bedsizes].multi_insert([
      { genome: 'hg38', ag_class: 'Histone', cl_class: 'Blood',
        qval: '05', number_of_lines: 150000, created_at: Time.now },
      { genome: 'hg38', ag_class: 'Histone', cl_class: 'Brain',
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
    DB[:runs].delete
    DB[:sra_cache].delete
    DB.run("DELETE FROM experiments_fts")
  end
end
