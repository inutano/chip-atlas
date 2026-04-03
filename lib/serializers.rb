# frozen_string_literal: true

module ChipAtlas
  module Serializers
    module_function

    def experiment(row)
      {
        expid:          row[:exp_id],
        genome:         row[:genome],
        agClass:        row[:ag_class],
        agSubClass:     row[:ag_sub_class],
        clClass:        row[:cl_class],
        clSubClass:     row[:cl_sub_class],
        title:          row[:title],
        attributes:     row[:attributes],
        readInfo:       row[:read_info],
        clSubClassInfo: row[:cl_sub_class_info],
      }
    end

    def classification_item(id, count = nil)
      { id: id, label: id, count: count }
    end

    def search_result(row)
      {
        expid:      row[:exp_id],
        sra_id:     row[:sra_id],
        geo_id:     row[:geo_id],
        genome:     row[:genome],
        agClass:    row[:ag_class],
        agSubClass: row[:ag_sub_class],
        clClass:    row[:cl_class],
        clSubClass: row[:cl_sub_class],
        title:      row[:title],
        attributes: row[:attributes],
      }
    end

    def normalize_condition(condition)
      {
        'genome'       => condition['genome'],
        'ag_class'     => condition['agClass'],
        'ag_sub_class' => condition['agSubClass'],
        'cl_class'     => condition['clClass'],
        'cl_sub_class' => condition['clSubClass'],
        'qval'         => condition['qval'],
        'antigen'      => condition['antigen'],
        'cellline'     => condition['cellline'],
        'distance'     => condition['distance'],
      }
    end
  end
end
