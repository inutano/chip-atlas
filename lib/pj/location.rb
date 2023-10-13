module PJ
  class Location
    def initialize(data)
      @data      = data
      @condition = data["condition"]
      @genome    = @condition["genome"]
    end

    #
    # Generate URL to browse remote data on IGV
    #

    def archive_base
      "https://chip-atlas.dbcls.jp/data/"
    end

    def fileformat
      ".bed"
    end

    def archive_url
      case @condition["agClass"]
      when "Annotation tracks"
        archived_annotation_url
      else
        archived_bed_url
      end
    end

    def archived_annotation_url
      @condition["clClass"] = 'All cell types'
      filename  = PJ::Bedfile.get_filename(@condition)
      File.join(archive_base, "annotations", @genome, filename)
    rescue NameError
      nil
    end

    def archived_bed_url
      filename  = PJ::Bedfile.get_filename(@condition)
      File.join(archive_base, @genome, "assembled", filename + fileformat)
    rescue NameError
      nil
    end

    def igv_url
      @data["igv"] || "http://localhost:60151"
    end

    def igv_browsing_url
      case @condition["agClass"]
      when "Annotation tracks"
        igv_browse_annotations
      else
        igv_browse_bedfile
      end
    end

    def igv_browse_annotations
      "#{igv_url}/load?genome=#{@genome}&file=#{archived_annotation_url}&name=#{PJ::Bedfile.get_trackname(@condition)}"
    end

    def igv_browse_bedfile
      "#{igv_url}/load?genome=#{@genome}&file=#{archived_bed_url}"
    end

    #
    # Generate URL to browse co-localization analysis result
    #

    def colo_url(type)
      antigen   = @condition["antigen"]
      cellline  = @condition["cellline"].gsub("\s","_")
      colo_base = File.join(archive_base, @genome, "colo")
      case type
      when "submit"
        "#{colo_base}/#{antigen}.#{cellline}.html"
      when "tsv"
        "#{colo_base}/#{antigen}.#{cellline}.tsv"
      when "gml"
        "#{colo_base}/#{cellline}.gml"
      end
    end

    #
    # Generate URL to browse target genes analysis result
    #

    def target_genes_url(type)
      antigen  = @condition["antigen"]
      distance = @condition["distance"]
      target_genes_base = File.join(archive_base, @genome, "target")
      fext = case type
             when "submit"
               "html"
             when "tsv"
               "tsv"
             end
      "#{target_genes_base}/#{antigen}.#{distance}.#{fext}"
    end


  end
end
