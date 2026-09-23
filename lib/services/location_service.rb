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
        # PB-19: both lookups must see the same merged condition. The old
        # code looked up the trackname against the caller's raw
        # cell_type_class (e.g. "NA") while the filename lookup silently
        # overrode it to "All cell types" -- so any Annotation tracks
        # request whose cell_type_class wasn't already "All cell types"
        # raised Bedfile::NotFound here, uncaught (production's
        # old-app/lib/pj/location.rb:30-36, 58-60 got away with this only
        # because Ruby happens to evaluate the trackname's string
        # interpolation after the filename lookup's condition mutation).
        condition_with_all = @condition.merge(cell_type_class: 'All cell types')
        filename  = ChipAtlas::Bedfile.get_filename(condition_with_all)
        trackname = ChipAtlas::Bedfile.get_trackname(condition_with_all).gsub(', ', '_')
        "#{igv}/load?genome=#{@genome}&file=#{ARCHIVE_BASE}/annotations/#{@genome}/#{filename}&name=#{trackname}"
      else
        "#{igv}/load?genome=#{@genome}&file=#{bed_url}"
      end
    rescue ChipAtlas::Bedfile::NotFound
      nil
    end

    # Colocalization result URLs
    def colo_tsv_url
      "#{colo_base}/#{encoded_track}.#{encoded_cell_type}.tsv"
    end

    def colo_gml_url
      "#{colo_base}/#{encoded_cell_type}.gml"
    end

    # Target genes result URLs
    def target_genes_tsv_url
      "#{target_genes_base}/#{encoded_track}.#{@condition[:distance]}.tsv"
    end

    # Comparative profile URLs
    def distribution_png_url
      "#{ARCHIVE_BASE}/#{@genome}/distribution/png/#{@condition[:experiment_id]}.dist.png"
    end

    def correlation_png_url
      "#{ARCHIVE_BASE}/#{@genome}/correlation/png/#{@condition[:experiment_id]}.cor.png"
    end

    def correlation_tsv_url
      # SV-41: production sanitises with gsub(/[^a-zA-Z0-9_-]/, '_')
      # (old-app/views/experiment.haml:333-338), not just spaces -- a plain
      # tr(' ', '_') left '+', '.', '/', ',' etc. in the URL and 404'd
      # against the data server for ~5.8% of antigen/cell-type names.
      track = @condition[:track_subclass].to_s.gsub(/[^a-zA-Z0-9_-]/, '_')
      cell  = @condition[:cell_type_subclass].to_s.gsub(/[^a-zA-Z0-9_-]/, '_')
      "#{ARCHIVE_BASE}/#{@genome}/correlation/tsv/#{@genome}__x__#{track}__x__#{cell}.tsv"
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
      extension = ChipAtlas::BedExtensionResolver.resolve(@genome, filename, ARCHIVE_BASE)
      "#{ARCHIVE_BASE}/#{@genome}/assembled/#{filename}#{extension}"
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
