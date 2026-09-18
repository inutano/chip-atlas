# frozen_string_literal: true

module ChipAtlas
  # Parses and serves the Target Genes result TSV
  # (`<genome>/target/<track>.<distance>.tsv`) that `LocationService
  # #target_genes_tsv_url` already points at correctly. There is no `.json`
  # counterpart on the data server — that endpoint has never existed (see
  # task B1's report and task B2's brief) — so this is the only source for
  # `/api/target_genes`.
  #
  # Shape of the TSV (verified live against mm10/target/Stat3.1.tsv,
  # 13,460 rows x 134 cols, 4.1 MB):
  #   col 1        Target_genes          gene symbol, e.g. "Stat3"
  #   col 2        <Track>|Average       mean score for the query TF
  #   cols 3..n-1  <SRX>|<CellType>      one column per experiment
  #   col n        STRING                STRING interaction score
  # Column count and the exact header names vary by antigen/genome, so
  # nothing here hardcodes 134 or "<Track>|Average" — the average column is
  # found positionally (index 1) with a "|Average" suffix check as a sanity
  # backstop (see #average_column_index).
  #
  # === Caching strategy ===
  #
  # A parsed entry (headers + row arrays, first column a String, the rest
  # Float) is cached per (genome, track, distance) rather than the raw TSV
  # text, because sorting/slicing text on every request would mean
  # re-splitting and re-parsing all ~1.8M cells per page click anyway — the
  # expensive part isn't the network fetch, it's turning tab-separated text
  # into a matrix. What is NOT cached is any particular sort/offset/limit
  # result: sorting a already-parsed 13,460-row array is cheap (one
  # `sort_by` pass, no re-parsing), so each request re-sorts from the cached
  # matrix instead of caching one entry per (sort, order, offset, limit)
  # combination, which would multiply memory use for no benefit.
  #
  # Memory per entry is real and gets large fast: a 13,460 x 134 matrix
  # holds ~1.8M cells. Ruby doesn't pack these — each row is its own Array
  # (roughly 40 bytes of object header plus 8 bytes per slot on 64-bit
  # MRI), and every numeric cell is a flonum (no extra heap allocation, but
  # still consumes its 8-byte slot). That's roughly:
  #   13,460 rows x (40 + 134 x 8) bytes ~= 13,460 x 1,112 bytes ~= 15 MB
  # for one entry — noticeably larger than the 4.1 MB raw TSV, because
  # Ruby's per-slot/per-object overhead is worse than the wire format's.
  # A handful of popular antigens (more experiment columns, i.e. a wider
  # matrix) can each run several times that. So the cache is bounded by an
  # *estimated byte budget* (see MAX_CACHE_BYTES), not just an entry count —
  # a count-only bound (as used by BedExtensionResolver, whose entries are a
  # few bytes each) doesn't protect memory when one entry can be tens of MB.
  # Eviction is FIFO (oldest insertion first) until the new entry fits the
  # budget; an entry that alone exceeds the budget is still returned to the
  # caller but is not stored, so one huge antigen can't wedge the cache.
  #
  # TTL is short (5 minutes) — precomputed analysis files change rarely, but
  # a short TTL keeps a stale/bad parse from pinning a genome for long and
  # keeps steady-state memory closer to "whatever is being actively viewed"
  # rather than "everything ever requested since boot".
  #
  # Not thread-safe (same caveat as BedExtensionResolver): concurrent loads
  # for the same key can both parse and both write. Acceptable for now.
  module TargetGenesTsv
    TTL = 300               # seconds; short on purpose, see module comment
    MAX_CACHE_BYTES = 150 * 1024 * 1024 # ~150 MB, ~10 entries at the ~15 MB/entry estimate above
    BYTES_PER_ROW_OVERHEAD = 40         # approx Ruby Array object header, 64-bit MRI
    BYTES_PER_SLOT = 8                  # approx pointer/flonum slot size, 64-bit MRI

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 500

    AVERAGE_COLUMN_SUFFIX = '|Average'
    AVERAGE_COLUMN_INDEX = 1 # column 2 (0-based 1): "<Track>|Average"

    # Raised when `sort` names a column that isn't in this TSV's header row.
    UnknownSortColumn = Class.new(StandardError)

    # Raised when the fetched body doesn't look like a Target Genes TSV at
    # all (no header row, or a header row with fewer than 2 columns). Kept
    # distinct from "not found" (nil body / 404 upstream) so the route can
    # return a different, distinguishable error for a genuinely missing
    # combination versus a combination that exists but came back malformed.
    ParseError = Class.new(StandardError)

    TEST_ENV_VALUES = %w[test].freeze

    # Raised when a test would reach the real data server because no
    # fetcher stub was installed. Mirrors
    # BedExtensionResolver::LiveProbeNotStubbed — exists so a forgotten stub
    # fails loudly under RACK_ENV=test instead of silently returning nil
    # (which would look exactly like a genuine 404 in a test).
    LiveFetchNotStubbed = Class.new(StandardError)

    @cache = {}
    @cache_bytes = 0
    @fetcher = nil

    module_function

    # Test-only hook: replace the network fetch with a stub. `callable` is
    # invoked as `callable.call(url)` and must return the TSV body (String)
    # or nil (not found).
    def fetcher=(callable)
      @fetcher = callable
      reset!
    end

    def reset!
      @cache = {}
      @cache_bytes = 0
    end

    # Returns { columns:, rows:, total:, offset:, limit: } for the given
    # condition, sorted/sliced server-side, or nil if the TSV doesn't exist
    # upstream (a genuinely missing combination). Raises ParseError if the
    # body exists but isn't a well-formed TSV, and UnknownSortColumn if
    # `sort` names a column this TSV doesn't have — both distinct from the
    # nil ("not found") case so callers can respond differently.
    def result(genome:, track:, distance:, tsv_url:, sort: nil, order: nil, offset: nil, limit: nil)
      entry = load(genome, track, distance, tsv_url)
      return nil unless entry

      sort_index = resolve_sort_index(entry[:headers], sort)
      descending = order.to_s.downcase != 'asc'
      limit_i = clamp_limit(limit)
      offset_i = [offset.to_i, 0].max

      sorted = entry[:rows].sort_by { |row| row[sort_index] }
      sorted.reverse! if descending
      page = sorted.slice(offset_i, limit_i) || []

      {
        columns: entry[:headers],
        rows: page,
        total: entry[:rows].size,
        offset: offset_i,
        limit: limit_i,
      }
    end

    def clamp_limit(limit)
      value = limit.nil? || limit.to_s.empty? ? DEFAULT_LIMIT : limit.to_i
      value = DEFAULT_LIMIT if value <= 0
      value.clamp(1, MAX_LIMIT)
    end

    # Loads the parsed matrix for (genome, track, distance), from cache when
    # fresh, else fetches + parses + caches it. Returns nil when the
    # upstream fetch itself returns nil (no such file); raises ParseError
    # when a body was fetched but couldn't be parsed as a Target Genes TSV.
    def load(genome, track, distance, tsv_url)
      key = [genome, track, distance].join('/')
      cached = @cache[key]
      return cached if cached && (Time.now - cached[:cached_at]) < TTL

      body = fetch_tsv(tsv_url)
      return nil unless body

      headers, rows = parse(body)
      entry = { headers: headers, rows: rows, cached_at: Time.now }
      store(key, entry)
      entry
    end

    def fetch_tsv(url)
      return @fetcher.call(url) if @fetcher

      raise_if_unstubbed_under_test!(url)
      ChipAtlas::DataProxy.fetch(url)
    end

    def raise_if_unstubbed_under_test!(url)
      return unless TEST_ENV_VALUES.include?(ENV['RACK_ENV']) || TEST_ENV_VALUES.include?(ENV['APP_ENV'])

      raise LiveFetchNotStubbed,
            "TargetGenesTsv would make a live request to #{url} under " \
            "RACK_ENV=#{ENV['RACK_ENV'].inspect}/APP_ENV=#{ENV['APP_ENV'].inspect}. " \
            'Stub ChipAtlas::TargetGenesTsv.fetcher= in this test.'
    end

    # Splits the TSV into a header row (Array of String) and data rows
    # (Array of Array; column 0 kept as String, every other column
    # converted with #to_f). Column count is read from the header, not
    # hardcoded — this file's width varies by antigen/genome. A row with
    # fewer/more fields than the header (malformed upstream data) is
    # padded/truncated to the header's width rather than raising, so one
    # bad line doesn't take down the whole matrix; #to_f on a non-numeric
    # or missing cell yields 0.0.
    def parse(body)
      lines = body.each_line(chomp: true).reject(&:empty?)
      raise ParseError, 'Target genes TSV has no header row' if lines.empty?

      headers = lines.shift.split("\t", -1)
      raise ParseError, 'Target genes TSV header has fewer than 2 columns' if headers.size < 2

      width = headers.size
      rows = lines.map do |line|
        cols = line.split("\t", -1)
        Array.new(width) do |i|
          i.zero? ? cols[i].to_s : cols[i].to_f
        end
      end

      [headers, rows]
    end

    # Finds the "<Track>|Average" column by suffix; falls back to the fixed
    # positional index (column 2) if no header carries that suffix, since
    # the query track's exact spelling can vary from the header's spelling
    # (case, aliasing) even though the column is always there positionally.
    def average_column_index(headers)
      idx = headers.index { |h| h.end_with?(AVERAGE_COLUMN_SUFFIX) }
      idx || AVERAGE_COLUMN_INDEX
    end

    def resolve_sort_index(headers, sort)
      return average_column_index(headers) if sort.nil? || sort.to_s.empty?

      idx = headers.index(sort)
      raise UnknownSortColumn, "Unknown sort column: #{sort.inspect}" unless idx

      idx
    end

    def store(key, entry)
      bytes = estimate_bytes(entry)
      return if bytes > MAX_CACHE_BYTES # one entry alone would blow the budget; serve, don't cache

      existing = @cache.delete(key)
      @cache_bytes -= existing[:bytes].to_i if existing
      evict_until_fits(bytes)

      entry[:bytes] = bytes
      @cache[key] = entry
      @cache_bytes += bytes
    end

    def evict_until_fits(incoming_bytes)
      while @cache.any? && (@cache_bytes + incoming_bytes) > MAX_CACHE_BYTES
        _oldest_key, oldest_entry = @cache.shift
        @cache_bytes -= oldest_entry[:bytes].to_i
      end
    end

    def estimate_bytes(entry)
      row_count = entry[:rows].size
      col_count = entry[:headers].size
      row_count * (BYTES_PER_ROW_OVERHEAD + (col_count * BYTES_PER_SLOT))
    end

    private_class_method :fetch_tsv, :raise_if_unstubbed_under_test!, :parse, :average_column_index,
                          :resolve_sort_index, :store, :evict_until_fits, :estimate_bytes, :clamp_limit
  end
end
