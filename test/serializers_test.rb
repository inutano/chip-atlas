# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/serializers'

class SerializersTest < Minitest::Test
  def test_experiment_serializer
    row = { exp_id: 'SRX018625', genome: 'hg38', ag_class: 'Histone',
            ag_sub_class: 'H3K4me3', cl_class: 'Blood', cl_sub_class: 'K-562',
            title: 'H3K4me3 in K-562', attributes: 'cell line',
            read_info: '15000000,50', cl_sub_class_info: 'ATCC' }

    result = ChipAtlas::Serializers.experiment(row)

    assert_equal 'SRX018625', result[:expid]
    assert_equal 'hg38', result[:genome]
    assert_equal 'Histone', result[:agClass]
    assert_equal 'H3K4me3', result[:agSubClass]
    assert_equal 'Blood', result[:clClass]
    assert_equal 'K-562', result[:clSubClass]
    assert_equal 'H3K4me3 in K-562', result[:title]
    assert_equal 'cell line', result[:attributes]
    assert_equal '15000000,50', result[:readInfo]
    assert_equal 'ATCC', result[:clSubClassInfo]
  end

  def test_classification_item_serializer
    result = ChipAtlas::Serializers.classification_item('Blood', 120)
    assert_equal({ id: 'Blood', label: 'Blood', count: 120 }, result)
  end

  def test_search_result_serializer
    fts_row = { exp_id: 'SRX018625', sra_id: 'SRA123',
                geo_id: 'GSM456', genome: 'hg38',
                ag_class: 'Histone', ag_sub_class: 'H3K4me3',
                cl_class: 'Blood', cl_sub_class: 'K-562',
                title: 'test', attributes: 'cell line' }

    result = ChipAtlas::Serializers.search_result(fts_row)

    assert_equal 'SRX018625', result[:expid]
    assert_equal 'SRA123', result[:sra_id]
    assert_equal 'GSM456', result[:geo_id]
    assert_equal 'Histone', result[:agClass]
  end

  def test_normalize_condition
    condition = {
      'genome' => 'hg38', 'agClass' => 'Histone', 'agSubClass' => 'H3K4me3',
      'clClass' => 'Blood', 'clSubClass' => 'K-562', 'qval' => '05',
      'antigen' => 'CTCF', 'cellline' => 'K-562', 'distance' => '5000'
    }
    result = ChipAtlas::Serializers.normalize_condition(condition)

    assert_equal 'hg38', result[:genome]
    assert_equal 'Histone', result[:ag_class]
    assert_equal 'H3K4me3', result[:ag_sub_class]
    assert_equal 'Blood', result[:cl_class]
    assert_equal 'K-562', result[:cl_sub_class]
    assert_equal '05', result[:qval]
    assert_equal 'CTCF', result[:antigen]
    assert_equal 'K-562', result[:cellline]
    assert_equal '5000', result[:distance]
  end
end
