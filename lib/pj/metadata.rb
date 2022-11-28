require 'open-uri'

module PJ
  class Metadata
    class << self
      #
      # Class methods for fetching metadata
      #

      def nbdc_base
        "https://chip-atlas.dbcls.jp/data"
      end

      def metadata_base
        File.join(nbdc_base, "metadata")
      end

      def util_base
        File.join(nbdc_base, "util")
      end

      def nbdc_file_url(fname)
        base = case fname
               when "fileList.tab"
                 metadata_base
               when "experimentList.tab"
                 metadata_base
               when "analysisList.tab"
                 metadata_base
               when "lineNum.tsv"
                 util_base
               end
        File.join(base, fname)
      end

      def fetch(dest_fpath)
        fname = dest_fpath.split("/").last
        url = nbdc_file_url(fname)
        content = open(url).read
        open(dest_fpath,"w"){|f| f.puts(content) }
      end
    end
  end
end
