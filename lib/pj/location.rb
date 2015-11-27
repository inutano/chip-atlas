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
      "http://dbarchive.biosciencedbc.jp/kyushu-u/"
    end

    def fileformat
      ".bed"
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
      "#{igv_url}/load?genome=#{@genome}&file=#{archived_bed_url}"
    end

    #
    # Generate URL to browse co-localization analysis result
    #

    def colo_url(data,type)
      antigen   = @condition["antigen"]
      cellline  = @condition["cellline"].gsub("\s","_")
      colo_base = File.join(archive_base, @genome, "colo")
      case type
      when "submit"
        # "#{app_root}/target_genes_result?base=#{base}/#{antigen}.#{distance}.html"
        "#{colo_base}/#{antigen}.#{cellline}.html"
      when "tsv"
        "#{colo_base}/#{antigen}.#{cellline}.tsv"
      when "gml"
        "#{colo_base}/#{cellline}.gml"
      end
    end

    

  end
end
