# frozen_string_literal: true

module ChipAtlas
  # Parses and serves the Colocalization result TSV
  # (`<genome>/colo/<track>.<cell_type>.tsv`) that `LocationService
  # #colo_tsv_url` already points at correctly. There is no `.json`
  # counterpart on the data server -- that endpoint has never existed (see
  # task B5's brief; task B2 found the identical defect for Target Genes) --
  # so this is the only source for `/api/colo`.
  #
  # Shape of the TSV (verified live against hg38/colo/STAT3.Blood.tsv,
  # 3,862 rows x 21 cols, 263 KB):
  #   col 1        Experiment            SRX id of the candidate partner
  #   col 2        Cell_subclass         that experiment's cell type
  #   col 3        Protein               that experiment's antigen
  #   col 4        <Track>|Average       mean concordance with the query's
  #                                      reference experiments (0-10ish)
  #   cols 5..n-1  <SRX>|<CellType>      one column per reference
  #                                      experiment: a peak-intensity
  #                                      concordance score. Production
  #                                      computes these as products of H/M/L
  #                                      "binding-level" weights (H=3, M=2,
  #                                      L=1), so the only values that can
  #                                      occur are {1,2,3,4,6,9}; 0 means "no
  #                                      shared-bin data" (N.D.). Verified
  #                                      live against the paired .html: a raw
  #                                      value of 10 appears exactly and only
  #                                      at a row's own reference-experiment
  #                                      column (comparing an experiment
  #                                      against itself) and always renders
  #                                      black/"Same" there -- 10 can never
  #                                      arise from the H/M/L product
  #                                      formula, so it is an unambiguous
  #                                      self-comparison sentinel, not an
  #                                      extra real score. The color/label
  #                                      mapping itself lives client-side
  #                                      (frontend/pages/colo-result.ts) --
  #                                      this module only parses the numbers.
  #   col n        STRING                STRING interaction score, 0-1000ish
  # Column count and the exact header names vary by antigen/genome. Unlike
  # Target Genes (lib/services/target_genes_tsv.rb), the leading identity
  # block here is 3 columns wide (Experiment/Cell_subclass/Protein), not 1,
  # so nothing here hardcodes 21 -- the Average column is found by its
  # "|Average" suffix, falling back to the fixed positional index only if no
  # header carries that suffix.
  #
  # === No pagination, no cache ===
  #
  # 263 KB is small enough to send whole in one response -- this does not
  # have Target Genes' size problem (4.1 MB / 134 columns), so unlike
  # TargetGenesTsv this module has no offset/limit slicing and no
  # byte-budget cache (see that module's comment for why one was needed
  # there). Every request re-fetches and re-parses; sorting happens
  # client-side against the one full payload already sent (see
  # frontend/pages/colo-result.ts) rather than a server round trip per
  # header click.
  module ColoTsv
    LEADING_TEXT_COLUMNS = 3 # Experiment, Cell_subclass, Protein
    AVERAGE_COLUMN_SUFFIX = '|Average'
    AVERAGE_COLUMN_INDEX = 3 # column 4 (0-based 3): "<Track>|Average"

    # Raised when the fetched body doesn't look like a Colocalization TSV at
    # all (no header row, or a header row too narrow to hold the leading
    # identity columns plus at least one data column). Kept distinct from
    # "not found" (nil body / 404 upstream) so the route can return a
    # different, distinguishable error for a genuinely missing combination
    # versus a combination that exists but came back malformed.
    ParseError = Class.new(StandardError)

    TEST_ENV_VALUES = %w[test].freeze

    # Raised when a test would reach the real data server because no
    # fetcher stub was installed. Mirrors TargetGenesTsv::LiveFetchNotStubbed
    # -- exists so a forgotten stub fails loudly under RACK_ENV=test instead
    # of silently returning nil (which would look exactly like a genuine 404
    # in a test).
    LiveFetchNotStubbed = Class.new(StandardError)

    @fetcher = nil

    module_function

    # Test-only hook: replace the network fetch with a stub. `callable` is
    # invoked as `callable.call(url)` and must return the TSV body (String)
    # or nil (not found).
    def fetcher=(callable)
      @fetcher = callable
    end

    # Returns { columns:, rows:, total: } sorted descending by the Average
    # column -- matching production's own default (the live STAT3/Blood
    # page reports "Sort key: STAT3 | Average") -- or nil if the TSV doesn't
    # exist upstream (a genuinely missing combination). Raises ParseError if
    # the body exists but isn't a well-formed Colocalization TSV.
    #
    # Takes only `tsv_url` (genome/track/cell_type are already baked into it
    # by LocationService#colo_tsv_url, and there is no per-condition cache
    # key to build here unlike TargetGenesTsv) -- the route adds
    # genome/track/cell_type back onto the JSON response itself.
    def result(tsv_url:)
      body = fetch_tsv(tsv_url)
      return nil unless body

      headers, rows = parse(body)
      avg_idx = average_column_index(headers)
      sorted = rows.sort_by { |row| -row[avg_idx] }

      { columns: headers, rows: sorted, total: sorted.size }
    end

    def fetch_tsv(url)
      return @fetcher.call(url) if @fetcher

      raise_if_unstubbed_under_test!(url)
      ChipAtlas::DataProxy.fetch(url)
    end

    def raise_if_unstubbed_under_test!(url)
      return unless TEST_ENV_VALUES.include?(ENV['RACK_ENV']) || TEST_ENV_VALUES.include?(ENV['APP_ENV'])

      raise LiveFetchNotStubbed,
            "ColoTsv would make a live request to #{url} under " \
            "RACK_ENV=#{ENV['RACK_ENV'].inspect}/APP_ENV=#{ENV['APP_ENV'].inspect}. " \
            'Stub ChipAtlas::ColoTsv.fetcher= in this test.'
    end

    # Splits the TSV into a header row (Array of String) and data rows
    # (Array of Array). The first LEADING_TEXT_COLUMNS columns (Experiment,
    # Cell_subclass, Protein) stay Strings; every other column (Average,
    # per-reference concordance, STRING) is converted with #to_f. A row with
    # fewer/more fields than the header is padded/truncated to the header's
    # width rather than raising, so one bad line doesn't take down the whole
    # matrix; #to_f on a non-numeric or missing cell yields 0.0.
    def parse(body)
      lines = body.each_line(chomp: true).reject(&:empty?)
      raise ParseError, 'Colocalization TSV has no header row' if lines.empty?

      headers = lines.shift.split("\t", -1)
      if headers.size <= LEADING_TEXT_COLUMNS
        raise ParseError, "Colocalization TSV header has fewer than #{LEADING_TEXT_COLUMNS + 1} columns"
      end

      width = headers.size
      rows = lines.map do |line|
        cols = line.split("\t", -1)
        Array.new(width) { |i| i < LEADING_TEXT_COLUMNS ? cols[i].to_s : cols[i].to_f }
      end

      [headers, rows]
    end

    # Finds the "<Track>|Average" column by suffix; falls back to the fixed
    # positional index (column 4) if no header carries that suffix, since
    # the query track's exact spelling can vary from the header's spelling
    # (case, aliasing) even though the column is always there positionally.
    def average_column_index(headers)
      idx = headers.index { |h| h.end_with?(AVERAGE_COLUMN_SUFFIX) }
      idx || AVERAGE_COLUMN_INDEX
    end

    private_class_method :fetch_tsv, :raise_if_unstubbed_under_test!, :parse, :average_column_index
  end
end
