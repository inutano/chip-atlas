require 'uri'

module ChipAtlas
  class LocationService
    ARCHIVE_BASE = 'https://chip-atlas.dbcls.jp/data/'.freeze

    def initialize(data)
      @data      = data
      @condition = data['condition']
      @genome    = @condition['genome']
    end

    def archive_url
      case @condition['agClass']
      when 'Annotation tracks' then annotation_url
      else bed_url
      end
    end

    def igv_browsing_url
      igv = @data['igv'] || 'http://localhost:60151'
      case @condition['agClass']
      when 'Annotation tracks'
        trackname = ChipAtlas::Bedfile.get_trackname(@condition).gsub(', ', '_')
        "#{igv}/load?genome=#{@genome}&file=#{annotation_url}&name=#{trackname}"
      else
        "#{igv}/load?genome=#{@genome}&file=#{bed_url}"
      end
    end

    def colo_url(type)
      antigen  = URI.encode_www_form_component(@condition['antigen'])
      cellline = URI.encode_www_form_component(@condition['cellline'].gsub(' ', '_'))
      base     = File.join(ARCHIVE_BASE, @genome, 'colo')
      case type
      when 'submit' then "#{base}/#{antigen}.#{cellline}.html"
      when 'tsv'    then "#{base}/#{antigen}.#{cellline}.tsv"
      when 'gml'    then "#{base}/#{cellline}.gml"
      end
    end

    def target_genes_url(type)
      antigen  = URI.encode_www_form_component(@condition['antigen'])
      distance = @condition['distance']
      base     = File.join(ARCHIVE_BASE, @genome, 'target')
      ext = type == 'submit' ? 'html' : 'tsv'
      "#{base}/#{antigen}.#{distance}.#{ext}"
    end

    private

    def bed_url
      filename = ChipAtlas::Bedfile.get_filename(@condition)
      File.join(ARCHIVE_BASE, @genome, 'assembled', filename + '.bed')
    rescue ChipAtlas::Bedfile::NotFound
      nil
    end

    def annotation_url
      condition_with_all = @condition.merge('clClass' => 'All cell types')
      filename = ChipAtlas::Bedfile.get_filename(condition_with_all)
      File.join(ARCHIVE_BASE, 'annotations', @genome, filename)
    rescue ChipAtlas::Bedfile::NotFound
      nil
    end
  end
end
