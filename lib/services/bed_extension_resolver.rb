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
  # winner per (genome, filename), so a genome that gets reprocessed starts
  # serving the new extension again without a deploy. A *confirmed* answer
  # (one of the probes actually returned 200) is cached for the full TTL; an
  # *assumed* answer (neither probe could be confirmed — timeout, archive
  # down, etc. — so we fell back to the first candidate) is cached only
  # briefly, so a transient outage doesn't pin a genome to a guess for an
  # hour. The cache is also size-bounded with FIFO eviction so it can't grow
  # without limit over the life of the process.
  #
  # Not thread-safe: concurrent resolves for the same key can both probe and
  # both write. Acceptable for now (see task A2 fix report) — add locking if
  # this ever needs to be safe under a threaded server.
  module BedExtensionResolver
    ARCHIVE_HOST = 'chip-atlas.dbcls.jp'
    CANDIDATE_EXTENSIONS = ['.bed', '.bed.gz'].freeze
    CONFIRMED_TTL = 3600  # 1 hour for a probe that actually returned 200
    ASSUMED_TTL   = 5     # seconds — an unconfirmed fallback is retried almost immediately
    MAX_CACHE_ENTRIES = 2000 # bound the process-lifetime cache; oldest entries evicted first
    PROBE_OPEN_TIMEOUT = 2  # seconds
    PROBE_READ_TIMEOUT = 2  # seconds

    # Raised when something would reach the real archive while the process
    # is under test and no stub has been installed. This exists so a test
    # that forgets to stub the probe fails loudly instead of silently
    # making a live network call (see task A2 fix report, item 1).
    LiveProbeNotStubbed = Class.new(StandardError)

    TEST_ENV_VALUES = %w[test].freeze

    @cache = {}
    @prober = nil
    @allow_live_probe = false

    module_function

    # Test-only hook: replace the network HEAD probe with a stub.
    # `callable` is invoked as `callable.call(url)` and must return true/false.
    def prober=(callable)
      @prober = callable
      reset!
    end

    # Explicit opt-in for a test that genuinely wants to exercise the real
    # network probe under RACK_ENV/APP_ENV=test (none currently do). Without
    # this, #live? raises LiveProbeNotStubbed rather than reaching the
    # network when no prober is set and the environment says "test".
    def allow_live_probe=(value)
      @allow_live_probe = value
    end

    def reset!
      @cache = {}
    end

    # Returns the extension (including the leading dot) that is currently
    # live for `<base_url>/<genome>/assembled/<filename><extension>`.
    def resolve(genome, filename, base_url)
      key = "#{genome}/#{filename}"
      entry = @cache[key]
      return entry[:extension] if entry && (Time.now - entry[:cached_at]) < entry[:ttl]

      extension, confirmed = probe(genome, filename, base_url)
      store(key, extension, confirmed)
      extension
    end

    # Returns [extension, confirmed] where confirmed is true only if a HEAD
    # probe actually returned 200 for that extension.
    def probe(genome, filename, base_url)
      CANDIDATE_EXTENSIONS.each do |ext|
        return [ext, true] if live?("#{base_url}/#{genome}/assembled/#{filename}#{ext}")
      end
      # Neither probe answered (archive unreachable, both missing, etc.) —
      # fall back to the first candidate so callers still get a URL to try,
      # but this is a guess, not a confirmed answer (see #store).
      [CANDIDATE_EXTENSIONS.first, false]
    end

    def live?(url)
      return @prober.call(url) if @prober
      raise_if_unstubbed_under_test!(url)

      uri = URI.parse(url)
      return false unless uri.host == ARCHIVE_HOST

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = PROBE_OPEN_TIMEOUT
      http.read_timeout = PROBE_READ_TIMEOUT
      response = http.head(uri.request_uri)
      response.code == '200'
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::HTTPError, OpenSSL::SSL::SSLError, IOError
      false
    end

    def raise_if_unstubbed_under_test!(url)
      return if @allow_live_probe
      return unless TEST_ENV_VALUES.include?(ENV['RACK_ENV']) || TEST_ENV_VALUES.include?(ENV['APP_ENV'])

      raise LiveProbeNotStubbed,
            "BedExtensionResolver would make a live HEAD request to #{url} " \
            "under RACK_ENV=#{ENV['RACK_ENV'].inspect}/APP_ENV=#{ENV['APP_ENV'].inspect}. " \
            'Stub ChipAtlas::BedExtensionResolver.prober= in this test (or set ' \
            '.allow_live_probe = true if a real network probe is intentional).'
    end

    def store(key, extension, confirmed)
      ttl = confirmed ? CONFIRMED_TTL : ASSUMED_TTL
      # Delete-then-reinsert so the key moves to the end for FIFO eviction
      # below, whether or not it already existed.
      @cache.delete(key)
      @cache[key] = { extension: extension, cached_at: Time.now, ttl: ttl }
      @cache.shift while @cache.size > MAX_CACHE_ENTRIES
    end

    private_class_method :probe, :live?, :raise_if_unstubbed_under_test!, :store
  end
end
