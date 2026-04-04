# frozen_string_literal: true

require 'uri'

module ChipAtlas
  class LocationService
    ARCHIVE_BASE = 'https://chip-atlas.dbcls.jp/data'

    def initialize(data)
      @data      = data
      @condition = data['condition'].transform_keys(&:to_sym)
      @genome    = @condition[:genome]
    end

    def archive_url
      case @condition[:track_class]
      when 'Annotation tracks' then annotation_url
      else bed_url
      end
    end

    def igv_browsing_url
      igv = @data['igv'] || 'http://localhost:60151'
      case @condition[:track_class]
      when 'Annotation tracks'
        trackname = ChipAtlas::Bedfile.get_trackname(@condition).gsub(', ', '_')
        "#{igv}/load?genome=#{@genome}&file=#{annotation_url}&name=#{trackname}"
      else
        "#{igv}/load?genome=#{@genome}&file=#{bed_url}"
      end
    end

    # Colocalization result URLs
    def colo_data_url
      "#{colo_base}/#{encoded_track}.#{encoded_cell_type}.json"
    end

    def colo_tsv_url
      "#{colo_base}/#{encoded_track}.#{encoded_cell_type}.tsv"
    end

    def colo_gml_url
      "#{colo_base}/#{encoded_cell_type}.gml"
    end

    # Target genes result URLs
    def target_genes_data_url
      "#{target_genes_base}/#{encoded_track}.#{@condition[:distance]}.json"
    end

    def target_genes_tsv_url
      "#{target_genes_base}/#{encoded_track}.#{@condition[:distance]}.tsv"
    end

    private

    def encoded_track
      URI.encode_www_form_component(@condition[:track])
    end

    def encoded_cell_type
      URI.encode_www_form_component(@condition[:cell_type].gsub(' ', '_'))
    end

    def colo_base
      "#{ARCHIVE_BASE}/#{@genome}/colo"
    end

    def target_genes_base
      "#{ARCHIVE_BASE}/#{@genome}/target"
    end

    def bed_url
      filename = ChipAtlas::Bedfile.get_filename(@condition)
      "#{ARCHIVE_BASE}/#{@genome}/assembled/#{filename}.bed"
    rescue ChipAtlas::Bedfile::NotFound
      nil
    end

    def annotation_url
      condition_with_all = @condition.merge(cell_type_class: 'All cell types')
      filename = ChipAtlas::Bedfile.get_filename(condition_with_all)
      "#{ARCHIVE_BASE}/annotations/#{@genome}/#{filename}"
    rescue ChipAtlas::Bedfile::NotFound
      nil
    end
  end
end
