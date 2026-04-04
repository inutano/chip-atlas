# frozen_string_literal: true

require 'uri'

module ChipAtlas
  class LocationService
    ARCHIVE_BASE = 'https://chip-atlas.dbcls.jp/data'.freeze

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

    def colo_url(type)
      track     = URI.encode_www_form_component(@condition[:track])
      cell_type = URI.encode_www_form_component(@condition[:cell_type].gsub(' ', '_'))
      base      = "#{ARCHIVE_BASE}/#{@genome}/colo"
      case type
      when 'submit' then "#{base}/#{track}.#{cell_type}.html"
      when 'tsv'    then "#{base}/#{track}.#{cell_type}.tsv"
      when 'gml'    then "#{base}/#{cell_type}.gml"
      end
    end

    def target_genes_url(type)
      track    = URI.encode_www_form_component(@condition[:track])
      distance = @condition[:distance]
      base     = "#{ARCHIVE_BASE}/#{@genome}/target"
      ext = type == 'submit' ? 'html' : 'tsv'
      "#{base}/#{track}.#{distance}.#{ext}"
    end

    private

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
