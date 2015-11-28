require 'open-uri'
require 'net/http'

module PJ
  class FastQC
    class << self
      def domain
        "data.dbcls.jp"
      end

      def path
        "/~inutano/fastqc"
      end

      def base
        "http://#{domain}/#{path}"
      end

      def get_images_url(exp_id, app_root)
        run_ids = exp2run(exp_id)
        run_ids.map{|runid| PJ::FastQC.new(run_id, app_root).images_url }.flatten
      end

      def exp2run(exp_id)
        h = open(File.join(app_root, "tables/exp2run.json")){|f| JSON.load(f) }
        h[exp_id]
      end
    end

    def initialize(run_id, app_root)
      @run_id = run_id
      @fpath = File.join(run_id.slice(0,3), run_id.slice(0,4), run_id.sub(/...$/,""), run_id)
      @app_root = app_root
    end

    def images_url
      fetch if !cached?
      cached_images
    end

    def remote_run_dir
      File.join(PJ::FastQC.fastqc_base, @fpath)
    end

    def local_run_dir
      File.join(PROJ_ROOT, "public/images/fastqc", @fpath)
    end

    def reads_suffix
      ["_fastqc","_1_fastqc","_2_fastqc"]
    end

    def local_images_url
      reads_suffix.map do |read|
        File.join(@app_root, "public/images/fastqc", @fpath, @run_id+read, "Images", "per_base_quality.png")
      end
    end

    def cached?
      status_list = local_images_url.map do |url|
        uri = URI(url)
        request = Net::HTTP.new(uri.host, uri.port)
        response = request.request_head(uri.path)
        response.code.to_i
      end
      status_list.include?(200)
    end

    def cached_images
      local_images_url.select{|url| remotefile_available?(url) }
    end

    def remotefile_available?(url)
      uri = URI(url)
      request = Net::HTTP.new(uri.host, uri.port)
      response = request.request_head(uri.path)
      response.code.to_i == 200
    end

    def fetch
      FileUtils.mkdir_p(local_run_dir) if !File.exist?(local_run_dir)
      Net::HTTP.start(PJ::FastQC.domain) do |http|
        reads_suffix.each do |suffix|
          read_fname = @run_id + suffix
          resp = http.get(File.join(PJ::FastQC.path, @fpath, read_fname))
          open(File.join(local_run_dir,read_fname), "wb") do |file|
            file.write(resp.body)
          end
        end
      end
      `unzip -d "#{local_run_dir}" "#{local_run_dir}/*zip"`
    end
  end
end
