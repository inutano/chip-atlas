require 'net/http'

module PJ
  class Location
    # URL of the IGV genome JSON configuration prepared by ChIP-Atlas
    def self.igv_genome_url(genome)
      "https://chip-atlas.dbcls.jp/data/genome/#{genome}/#{genome}.json"
    end

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

    # Assembled BED files are served gzipped. Fall back to plain .bed for
    # older entries that have no .bed.gz (some of hg19, mm9, dm3 and ce10)
    def archived_bed_url
      filename  = PJ::Bedfile.get_filename(@condition)
      bed_url   = File.join(archive_base, @genome, "assembled", filename + ".bed")
      remote_file_missing?(bed_url + ".gz") ? bed_url : bed_url + ".gz"
    rescue NameError
      nil
    end

    # The data server occasionally stalls on connect, so retry with a short
    # timeout. Assume the file exists if the server cannot be reached.
    def remote_file_missing?(url, attempts: 3)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 1, read_timeout: 3) do |http|
        http.request_head(uri.path).code == "404"
      end
    rescue StandardError
      (attempts -= 1) > 0 ? retry : false
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
      "#{igv_url}/load?genome=#{PJ::Location.igv_genome_url(@genome)}&file=#{archived_annotation_url}&name=#{PJ::Bedfile.get_trackname(@condition).gsub(', ','_')}"
    end

    def igv_browse_bedfile
      "#{igv_url}/load?genome=#{PJ::Location.igv_genome_url(@genome)}&file=#{archived_bed_url}"
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
