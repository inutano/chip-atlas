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

    def search_result(fts_row)
      {
        expid:      fts_row['exp_id'],
        sra_id:     fts_row['sra_id'],
        geo_id:     fts_row['geo_id'],
        genome:     fts_row['genome'],
        agClass:    fts_row['ag_class'],
        agSubClass: fts_row['ag_sub_class'],
        clClass:    fts_row['cl_class'],
        clSubClass: fts_row['cl_sub_class'],
        title:      fts_row['title'],
        attributes: fts_row['attributes'],
      }
    end
  end
end
