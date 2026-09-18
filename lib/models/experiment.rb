# frozen_string_literal: true

require 'yaml'
require 'json'
require 'set'

module ChipAtlas
  module Experiment
    # The supported genome set lives in config/genomes.yml so it can change
    # without a code edit. File order is the order shown in every genome tab
    # strip (see frontend/components/genome-tabs.ts).
    DEFAULT_GENOMES_CONFIG_PATH = File.expand_path(File.join('..', '..', 'config', 'genomes.yml'), __dir__).freeze

    EXPERIMENT_TYPES = [
      { id: 'Histone',          label: 'ChIP: Histone' },
      { id: 'RNA polymerase',   label: 'ChIP: RNA polymerase' },
      { id: 'TFs and others',   label: 'ChIP: TFs and others' },
      { id: 'Input control',    label: 'ChIP: Input control' },
      { id: 'ATAC-Seq',         label: 'ATAC-Seq' },
      { id: 'DNase-seq',        label: 'DNase-seq' },
      { id: 'Bisulfite-Seq',    label: 'Bisulfite-Seq' },
      { id: 'CUT&Tag',          label: 'CUT&Tag' },
      { id: 'CUT&RUN',          label: 'CUT&RUN' },
      { id: 'Annotation tracks', label: 'Annotation tracks' },
    ].freeze

    @index_cache = nil
    @index_cache_at = nil
    INDEX_CACHE_TTL = 3600  # 1 hour

    @genomes_config_path = DEFAULT_GENOMES_CONFIG_PATH
    @genomes = nil
    @genome_order = nil

    module_function

    # Test-only hook: point the registry at a different YAML fixture. Resets
    # the memo so the next #genomes/#genome_order call re-reads the file.
    def genomes_config_path=(path)
      @genomes_config_path = path
      reset_genomes!
    end

    def genomes_config_path
      @genomes_config_path
    end

    # Test-only hook: put the registry back on config/genomes.yml.
    def reset_genomes_config_path!
      @genomes_config_path = DEFAULT_GENOMES_CONFIG_PATH
      reset_genomes!
    end

    # Clears the memoized genome registry so the next read picks up whatever
    # is currently at genomes_config_path.
    def reset_genomes!
      @genomes = nil
      @genome_order = nil
    end

    # id => label, in config file order. Memoized after first read.
    def genomes
      @genomes ||= load_genomes_config
    end

    # id => sort position, derived from #genomes.
    def genome_order
      @genome_order ||= genomes.keys.each_with_index.to_h.freeze
    end

    def load_genomes_config
      config = YAML.safe_load(File.read(genomes_config_path))
      entries = config['genomes'] || []
      entries.each_with_object({}) { |entry, hash| hash[entry['id']] = entry['label'] }.freeze
    end

    def formatted_experiment_count
      count = number_of_experiments
      rounded = (count / 1000) * 1000
      rounded.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')
    end

    def stats
      genomes = {}
      dataset.group_and_count(:genome).each do |row|
        genomes[row[:genome]] = row[:count]
      end

      track_classes = {}
      dataset.group_and_count(:track_class).each do |row|
        track_classes[row[:track_class]] = row[:count]
      end

      {
        total_experiments: number_of_experiments,
        total_experiments_formatted: formatted_experiment_count,
        by_genome: genomes,
        by_track_class: track_classes,
      }
    end

    def cached_index_all_genome
      now = Time.now
      if @index_cache && @index_cache_at && (now - @index_cache_at) < INDEX_CACHE_TTL
        return @index_cache
      end

      @index_cache = index_all_genome
      @index_cache_at = now
      @index_cache
    end

    def dataset
      DB[:experiments]
    end

    def list_of_genome
      genomes
    end

    def list_of_experiment_types
      EXPERIMENT_TYPES
    end

    def experiment_types(genome, cell_type_class)
      subset = dataset.where(genome: genome)
      subset = subset.where(cell_type_class: cell_type_class) unless cell_type_class == 'All cell types'
      counts = subset.group_and_count(:track_class).as_hash(:track_class, :count)

      EXPERIMENT_TYPES.map do |t|
        { id: t[:id], label: t[:label], count: counts[t[:id]] }
      end
    end

    def sample_types(genome, track_class)
      track_class = EXPERIMENT_TYPES.first[:id] if track_class == 'undefined'

      groups = dataset.where(genome: genome, track_class: track_class)
                      .group_and_count(:cell_type_class)

      total = 0
      result = []
      groups.each do |row|
        result << { id: row[:cell_type_class], label: row[:cell_type_class], count: row[:count] }
        total += row[:count]
      end

      result.unshift({ id: 'All cell types', label: 'All cell types', count: total })
      result
    end

    def chip_antigen(genome, track_class, cell_type_class)
      track_class = EXPERIMENT_TYPES.first[:id] if track_class == 'undefined'
      result = [{ id: '-', label: 'All', count: nil }]

      subset = dataset.where(genome: genome, track_class: track_class)
      unless cell_type_class == 'undefined' || cell_type_class == 'All cell types'
        subset = subset.where(cell_type_class: cell_type_class)
      end

      subset.group_and_count(:track_subclass).each do |row|
        result << { id: row[:track_subclass], label: row[:track_subclass], count: row[:count] }
      end
      result
    end

    def cell_type(genome, track_class, cell_type_class)
      result = [{ id: '-', label: 'All', count: nil }]

      if cell_type_class != 'undefined' && cell_type_class != 'All cell types'
        track_class = EXPERIMENT_TYPES.first[:id] if track_class == 'undefined'
        subset = dataset.where(genome: genome, track_class: track_class, cell_type_class: cell_type_class)
        subset.group_and_count(:cell_type_subclass).each do |row|
          result << { id: row[:cell_type_subclass], label: row[:cell_type_subclass], count: row[:count] }
        end
      end
      result
    end

    def record_by_experiment_id(experiment_id)
      dataset.where(experiment_id: experiment_id)
        .select(:experiment_id, :genome, :track_class, :track_subclass, :cell_type_class, :cell_type_subclass,
                :title, :attributes, :read_info, :cell_type_subclass_info)
        .all
        .sort_by { |r| genome_order.fetch(r[:genome], 999) }
    end

    def id_valid?(experiment_id)
      !dataset.where(experiment_id: experiment_id).empty?
    end

    def number_of_experiments
      dataset.distinct.select(:experiment_id).count
    end

    def total_number_of_reads(ids)
      return 0 if ids.nil? || ids.empty?

      placeholders = ids.map { '?' }.join(', ')
      sql = "SELECT COALESCE(SUM(CAST(SUBSTR(read_info, 1, INSTR(read_info, ',') - 1) AS INTEGER)), 0) AS total FROM experiments WHERE experiment_id IN (#{placeholders})"
      DB[sql, *ids].first[:total]
    end

    def index_all_genome
      result = {}
      genomes.each_key { |g| result[g] = { track: {}, cell_type: {} } }

      # One query for all track counts across all genomes
      dataset.group_and_count(:genome, :track_class, :track_subclass).each do |row|
        g = row[:genome]
        next unless result.key?(g)
        result[g][:track][row[:track_class]] ||= Hash.new(0)
        result[g][:track][row[:track_class]][row[:track_subclass]] = row[:count]
      end

      # One query for all cell_type counts across all genomes
      dataset.group_and_count(:genome, :cell_type_class, :cell_type_subclass).each do |row|
        g = row[:genome]
        next unless result.key?(g)
        result[g][:cell_type][row[:cell_type_class]] ||= Hash.new(0)
        result[g][:cell_type][row[:cell_type_class]][row[:cell_type_subclass]] = row[:count]
      end

      result
    end

    # Loads the `experiments` table and the `experiments_fts` search index
    # from ONE RECONCILED ROW SET, so the two stores can never drift apart
    # the way they used to. That set does not come from a single file -
    # experimentList.tab and ExperimentList_adv.json each carry data the
    # other doesn't:
    #
    #   experimentList.tab       - per-(experiment_id, genome) rows, with
    #                               real QC stats (read_info). No sra_id or
    #                               geo_id column at all.
    #   ExperimentList_adv.json  - one row per experiment_id, with a real
    #                               sra_id and geo_id. No QC stats. Its
    #                               genome field lists every assembly the
    #                               experiment's species has ever used
    #                               (comma-joined, e.g. "hg19, hg38"), NOT
    #                               necessarily what this specific
    #                               experiment was aligned against - that's
    #                               what produced the 219-row orphan bug
    #                               this task exists to close (see
    #                               task-A3-report.md).
    #
    # Reconciliation rule (tab wins for membership, JSON wins for content
    # it alone has):
    #   - `experiments` = every (experiment_id, genome) pair that survives
    #     experimentList.tab's genome filter, full stop, with the tab's own
    #     fields (QC stats included). The tab file is the only source with
    #     genuine per-genome evidence (QC numbers), so it alone decides
    #     what counts as a real, view-able experiment row. `experiments`
    #     does NOT carry sra_id/geo_id - nothing reads them from there
    #     (record_by_experiment_id doesn't select them, no route touches
    #     them, and ExperimentSearch.gsm_to_srx reads experiments_fts'
    #     copy). The JSON lookup below exists to feed experiments_fts, not
    #     to duplicate data onto a table nothing queries it from.
    #   - `experiments_fts` = the INTERSECTION: only (experiment_id, genome)
    #     pairs that BOTH experimentList.tab has (after its genome filter)
    #     AND ExperimentList_adv.json's own (comma-split, genome-filtered)
    #     genome list confirms for that id, minus Annotation tracks (see
    #     ChipAtlas::ExperimentSearch::NOT_INDEXED_TRACK_CLASSES). This is
    #     what makes the orphan bug structurally impossible: a search hit
    #     can only exist for a pair the tab file also vouches for, so it can
    #     never point at a /view page that doesn't exist. Every FTS row's
    #     fields (title, attributes, track_class, track_subclass,
    #     cell_type_class, cell_type_subclass, sra_id, geo_id) come from the
    #     JSON, not the tab, since experiments_fts is what actually
    #     surfaces those fields (search results, /view?id=GSM... redirects).
    #
    # Rows on either side of that intersection are exactly the drift this
    # task exists to kill - dropped, not silently discarded: the returned
    # stats hash reports how many fall in each direction so a load can be
    # audited instead of trusted blindly.
    #
    # Returns { experiments:, indexed:, tab_only:, json_only: } - see above.
    def load_from_files(table_path, json_path)
      timestamp = Time.now
      json_index = load_json_index(json_path)
      stats = { experiments: 0, indexed: 0, tab_only: 0, json_only: 0 }
      seen_pairs = Set.new
      batch_size = 5_000

      DB.transaction do
        records = []
        fts_records = []

        File.foreach(table_path, encoding: 'UTF-8') do |line_n|
          cols = line_n.chomp.split("\t")

          # The genome field is a single id in experimentList.tab, but the
          # loader this replaced was bitten hard by a source that sometimes
          # packed multiple genomes into one comma-joined field - matching
          # that against the id registry directly silently dropped ~95% of
          # the index (see load_json_index below, where that source really
          # does do this). Splitting defensively here costs nothing today
          # and keeps that failure mode closed if experimentList.tab's
          # format ever regresses toward it.
          genome = cols[1].to_s.split(/,\s*/).first
          next unless genomes.key?(genome)

          experiment_id           = cols[0]
          track_class              = cols[2]
          track_subclass           = cols[3]
          cell_type_class          = cols[4]
          cell_type_subclass       = cols[5]
          cell_type_subclass_info  = cols[6]
          read_info                = cols[7]
          title                    = cols[8]
          attributes               = cols[9..].to_a.join("\t")

          # Looked up (by experiment_id - the JSON has no per-genome
          # granularity) only to decide FTS inclusion and to supply
          # experiments_fts' fields below. experiments itself does not
          # carry sra_id/geo_id - see the method comment for why.
          json_row = json_index[experiment_id]

          records << {
            experiment_id:           experiment_id,
            genome:                  genome,
            track_class:             track_class,
            track_subclass:          track_subclass,
            cell_type_class:         cell_type_class,
            cell_type_subclass:      cell_type_subclass,
            cell_type_subclass_info: cell_type_subclass_info,
            read_info:               read_info,
            title:                   title,
            attributes:              attributes,
            created_at:              timestamp,
          }
          seen_pairs << [experiment_id, genome]

          confirmed = json_row && json_row[:genomes].include?(genome)
          if confirmed
            # Annotation tracks stay out of the search index - see
            # ChipAtlas::ExperimentSearch::NOT_INDEXED_TRACK_CLASSES. In
            # the current data this is moot (Annotation-tracks ids never
            # appear in the JSON at all, so they never reach `confirmed`),
            # but the check stays as the explicit rule rather than an
            # accident of that absence.
            if ChipAtlas::ExperimentSearch.indexable?(json_row[:track_class])
              fts_records << {
                experiment_id:      experiment_id,
                sra_id:             json_row[:sra_id],
                geo_id:             json_row[:geo_id],
                genome:             genome,
                track_class:        json_row[:track_class],
                track_subclass:     json_row[:track_subclass],
                cell_type_class:    json_row[:cell_type_class],
                cell_type_subclass: json_row[:cell_type_subclass],
                title:              json_row[:title],
                attributes:         json_row[:attributes],
              }
            end
          else
            # In the tab file, confirmed by no genome the JSON claims for
            # this id (or the id isn't in the JSON at all) - kept in
            # `experiments` (the tab is still authoritative for that), but
            # correctly excluded from the search index instead of trusting
            # an unconfirmed JSON genome claim.
            stats[:tab_only] += 1
          end

          if records.size >= batch_size
            dataset.multi_insert(records)
            stats[:experiments] += records.size
            records.clear
          end

          if fts_records.size >= batch_size
            ChipAtlas::ExperimentSearch.dataset.multi_insert(fts_records)
            stats[:indexed] += fts_records.size
            fts_records.clear
          end
        end

        if records.any?
          dataset.multi_insert(records)
          stats[:experiments] += records.size
        end

        if fts_records.any?
          ChipAtlas::ExperimentSearch.dataset.multi_insert(fts_records)
          stats[:indexed] += fts_records.size
        end
      end

      # The other direction of drift: (experiment_id, genome) pairs the
      # JSON claims that the tab file never backs up - exactly the shape of
      # the 219-row orphan bug this task closes. Never silently dropped:
      # counted and reported, not indexed.
      json_index.each do |experiment_id, row|
        row[:genomes].each do |genome|
          stats[:json_only] += 1 unless seen_pairs.include?([experiment_id, genome])
        end
      end

      ChipAtlas::ExperimentSearch.reset_total_count_cache!
      stats
    end

    # Parses ExperimentList_adv.json into { experiment_id => {...} }. One
    # row per experiment_id in the source (confirmed: 454,151 rows, 454,151
    # unique ids in the 2026-09-13 snapshot) - no per-genome duplication to
    # reconcile here, only per-experiment fields (sra_id, geo_id, and the
    # rest of the search-index content) plus the genome list load_from_files
    # checks each tab row's genome against.
    def load_json_index(json_path)
      rows = JSON.parse(File.read(json_path))['data'] || []
      index = {}

      rows.each do |row|
        experiment_id = row[0]

        # The genome field here is a comma-joined string like "hg19, hg38"
        # (sometimes truly an Array, depending on source revision) - NOT
        # one bare id. This is the exact field that, matched directly
        # against the genome registry instead of split first, silently
        # dropped ~95% of the search index the last time this codebase
        # touched it. Split, trim, and filter through the same
        # config/genomes.yml-backed registry as everything else.
        genome_field = row[3]
        genome_list = genome_field.is_a?(Array) ? genome_field : genome_field.to_s.split(/,\s*/)
        kept_genomes = genome_list.map(&:strip).reject(&:empty?).select { |g| genomes.key?(g) }
        next if kept_genomes.empty?

        index[experiment_id] = {
          sra_id:             row[1].to_s,
          geo_id:             row[2].to_s,
          genomes:            kept_genomes.to_set,
          track_class:        row[4].to_s,
          track_subclass:     row[5].to_s,
          cell_type_class:    row[6].to_s,
          cell_type_subclass: row[7].to_s,
          title:              row[8].to_s,
          attributes:         row[9].to_s,
        }
      end

      index
    end
  end
end
