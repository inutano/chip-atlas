# frozen_string_literal: true

require 'net/http'
require 'uri'

module ChipAtlas
  # The archive is mid-migration to gzip, genome by genome (some genomes
  # serve `<name>.bed`, others `<name>.bed.gz`, and which is which keeps
  # changing while the app runs). So the extension can't live in config or be
  # hardcoded — it has to be answered by the archive itself, at request time.
  #
  # This resolver probes the candidate extensions in order and caches the
  # winner per (genome, filename) for a bounded TTL, so a genome that gets
  # reprocessed starts serving the new extension again without a deploy.
  module BedExtensionResolver
    ARCHIVE_HOST = 'chip-atlas.dbcls.jp'
    CANDIDATE_EXTENSIONS = ['.bed', '.bed.gz'].freeze
    TTL = 3600 # 1 hour, same order of magnitude as Experiment's index cache

    @cache = {}
    @prober = nil

    module_function

    # Test-only hook: replace the network HEAD probe with a stub.
    # `callable` is invoked as `callable.call(url)` and must return true/false.
    def prober=(callable)
      @prober = callable
      reset!
    end

    def reset!
      @cache = {}
    end

    # Returns the extension (including the leading dot) that is currently
    # live for `<base_url>/<genome>/assembled/<filename><extension>`.
    def resolve(genome, filename, base_url)
      key = "#{genome}/#{filename}"
      entry = @cache[key]
      return entry[:extension] if entry && (Time.now - entry[:cached_at]) < TTL

      extension = probe(genome, filename, base_url)
      @cache[key] = { extension: extension, cached_at: Time.now }
      extension
    end

    def probe(genome, filename, base_url)
      CANDIDATE_EXTENSIONS.each do |ext|
        return ext if live?("#{base_url}/#{genome}/assembled/#{filename}#{ext}")
      end
      # Neither probe answered (archive unreachable, both missing, etc.) —
      # fall back to the first candidate so callers still get a URL to try.
      CANDIDATE_EXTENSIONS.first
    end

    def live?(url)
      return @prober.call(url) if @prober

      uri = URI.parse(url)
      return false unless uri.host == ARCHIVE_HOST

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.head(uri.request_uri)
      response.code == '200'
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError, OpenSSL::SSL::SSLError, IOError
      false
    end
  end
end
