# frozen_string_literal: true

require 'json'

module ChipAtlas
  module Analysis
    TARGET_GENES_DISTANCES = [
      { id: '1', label: '1 kb' },
      { id: '5', label: '5 kb' },
      { id: '10', label: '10 kb' },
    ].freeze

    # --- Human Target Genes index: stopgap snapshot -------------------------
    #
    # analysisList.tab is repurposed as the Target Genes index: each row is
    # (TF.kb, cell_list, target_genes_flag, genome), and it currently has
    # ZERO rows for any human genome even though the human data files exist
    # on the archive (e.g. hg38/target/STAT3.1.tsv -> 200) - that is an
    # upstream bug tracked separately (see task B1's brief, Q4). Until the
    # regenerated analysisList.tab covers human, #target_genes_result
    # backfills any genome the tab has no rows for at all from a vendored
    # snapshot of production's /data/target_genes_analysis.json, captured
    # 2026-09-19 (public/target_genes_analysis.snapshot-20260919.json, 49KB,
    # keys ce10 ce11 dm3 dm6 hg19 hg38 mm10 mm9 rn6 sacCer3; hg38 = 1,766
    # names). The app never fetches chip-atlas.org itself, at runtime or at
    # build time - this file is committed and read locally only.
    #
    # Once upstream lands and analysisList.tab covers human, delete
    # DEFAULT_HUMAN_SNAPSHOT_PATH, #human_snapshot_path(=), #human_snapshot,
    # the snapshot file, and the backfill loop in #target_genes_result - the
    # DB-only path already handles every genome correctly on its own.
    DEFAULT_HUMAN_SNAPSHOT_PATH = File.expand_path(
      File.join('..', '..', 'public', 'target_genes_analysis.snapshot-20260919.json'), __dir__
    ).freeze

    @human_snapshot_path = DEFAULT_HUMAN_SNAPSHOT_PATH
    @human_snapshot = nil

    # TODO(B4): once the colo index build exists, replace this explicit
    # allowlist with a check derived from which genomes actually have a colo
    # index (the archive has no `colo/` directory at all under TAIR12 today,
    # and there is no reliable signal for "has colo data" in this table yet —
    # see task A2's report for why an allowlist was used instead of deriving
    # this from the `analyses` table).
    GENOMES_WITH_COLO = %w[hg38 mm10 rn6 dm6 ce11 sacCer3].freeze

    module_function

    def target_genes_distances
      TARGET_GENES_DISTANCES
    end

    # Test-only hook: point the human snapshot at a different JSON fixture.
    # Resets the memo so the next #target_genes_result re-reads the file.
    def human_snapshot_path=(path)
      @human_snapshot_path = path
      @human_snapshot = nil
    end

    def human_snapshot_path
      @human_snapshot_path
    end

    # Test-only hook: put the snapshot path back on the real vendored file.
    def reset_human_snapshot_path!
      @human_snapshot_path = DEFAULT_HUMAN_SNAPSHOT_PATH
      @human_snapshot = nil
    end

    def human_snapshot
      @human_snapshot ||= JSON.parse(File.read(human_snapshot_path))
    end

    # Genome tab strip for /colo: the full registry, filtered down to genomes
    # known to have colocalization data. Preserves config/genomes.yml order.
    def genomes_with_colo
      ChipAtlas::Experiment.genomes.select { |id, _| GENOMES_WITH_COLO.include?(id) }
    end

    def dataset
      DB[:analyses]
    end

    def colo_result_by_genome(genome)
      result = { genome => { track: {}, cell_type: {} } }

      dataset.where(genome: genome).each do |row|
        cell_list = row[:cell_list].to_s.split(',')
        next if cell_list.empty?

        track = row[:track]
        result[genome][:track][track] = cell_list

        cell_list.each do |cl|
          result[genome][:cell_type][cl] ||= []
          result[genome][:cell_type][cl] << track
        end
      end
      result
    end

    # genome -> bare antigen names with precomputed Target Genes data.
    # `track` is already bare (see #load_from_file) so this just dedupes the
    # per-distance rows down to one entry per antigen, then backfills any
    # genome the tab has no rows for at all - see the stopgap comment above.
    # Rows #load_from_file could not resolve to a known distance (distance
    # IS NULL) are excluded: no valid <track>.<distance>.tsv can exist for
    # them, so offering them in the picker would just reproduce the original
    # bug (an antigen name the archive can never match).
    def target_genes_result
      result = {}
      dataset.where(target_genes: true).exclude(distance: nil).each do |row|
        genome = row[:genome]
        result[genome] ||= []
        result[genome] << row[:track]
      end
      result.each_value(&:uniq!)

      ChipAtlas::Experiment.genomes.each_key do |genome|
        next if result.key?(genome)

        fallback = human_snapshot[genome]
        result[genome] = fallback if fallback
      end

      result
    end

    # Splits a raw analysisList.tab track field ("Acaa2.10") into its bare
    # antigen name and TSS distance in kb ("Acaa2", "10"). Distance is
    # always the last dot-separated segment IF that segment is one of the
    # known distance ids (see TARGET_GENES_DISTANCES, the one source for
    # that set in this file) - so this splits on the LAST dot only, and
    # only when the trailing piece is actually a distance. That guard
    # matters for two reasons at once: antigen names that themselves
    # contain a dot (e.g. "wdr-5.1", which appears in the file as
    # "wdr-5.1.1", "wdr-5.1.5", "wdr-5.1.10") must not be corrupted by a
    # naive `split('.')`, and a row whose trailing component ISN'T a
    # distance at all (a future feed-shape change, not seen in the file
    # today) must not be silently mangled into a wrong track/distance pair
    # either - it stays whole. A raw value with no dot, or whose trailing
    # segment doesn't match a known distance id, is kept whole as `track`
    # with a nil `distance` rather than guessed at.
    def split_track_and_distance(raw)
      return [raw, nil] unless raw.include?('.')

      track, _sep, distance = raw.rpartition('.')
      return [raw, nil] unless TARGET_GENES_DISTANCES.any? { |d| d[:id] == distance }

      [track, distance]
    end

    # Returns { total:, unrecognized_shape: } - unrecognized_shape counts
    # rows whose track field #split_track_and_distance could not resolve to
    # a known distance (see there). Those rows are still stored (distance
    # NULL) so nothing about the source file is silently thrown away, but
    # #target_genes_result excludes them from the picker index. Expected to
    # be 0 against today's analysisList.tab; the point of counting and
    # reporting it (see lib/tasks/metadata.rake's load_analysis task) is
    # that a feed-shape change shows up in the load output instead of
    # silently mangling data one layer down - the same failure mode task A3
    # closed for experiments/experiments_fts.
    def load_from_file(table_path)
      timestamp = Time.now
      total = 0
      unrecognized_shape = 0
      batch_size = 5_000

      DB.transaction do
        records = []

        File.foreach(table_path, encoding: 'UTF-8') do |line_n|
          cols = line_n.chomp.split("\t")
          genome = cols[3]
          next unless ChipAtlas::Experiment.genomes.key?(genome)

          track, distance = split_track_and_distance(cols[0])
          unrecognized_shape += 1 if distance.nil?

          records << {
            track:        track,
            distance:     distance,
            cell_list:    cols[1],
            target_genes: cols[2] == '+',
            genome:       genome,
            created_at:   timestamp,
          }

          if records.size >= batch_size
            dataset.multi_insert(records)
            total += records.size
            records.clear
          end
        end

        if records.any?
          dataset.multi_insert(records)
          total += records.size
        end
      end
      { total: total, unrecognized_shape: unrecognized_shape }
    end
  end
end
