# frozen_string_literal: true

require 'json'

module ChipAtlas
  module Analysis
    TARGET_GENES_DISTANCES = [
      { id: '1', label: '1 kb' },
      { id: '5', label: '5 kb' },
      { id: '10', label: '10 kb' },
    ].freeze

    # analysisList.tab is a COMBINED index and has had the same four columns
    # since 2015: antigen, cell_list, target_genes_flag, genome. `cell_list`
    # is the Colocalization index - the cell-type classes that antigen has
    # colo results for - and the flag says whether it also has Target Genes
    # output. There is no distance dimension in it and there never was; the
    # TSS distance lives in the filenames (CTCF.1.tsv / .5 / .10) and in
    # TARGET_GENES_DISTANCES above, which is the UI's fixed set.
    #
    # An earlier build of this file (2026-09-09..13) was broken three ways at
    # once - cell_list blanked to "-" on every row, every human row dropped,
    # and a ".1"/".5"/".10" suffix appended to the antigen name - and this
    # app was built against it: a `distance` column, a splitter for that
    # suffix, and a vendored snapshot of production's Target Genes index to
    # paper over the missing human rows. All of that is gone, along with the
    # reading of the file it encoded. #load_from_file now watches for that
    # build returning, because ingesting it silently is what cost the time.
    #
    # Verified against the 2026-09-22 build: `cell_list` reproduces
    # production's /data/colo_analysis.json for all ten genomes it serves
    # (6,251 antigens, every cell-type list), and the rows flagged "+"
    # reproduce its /data/target_genes_analysis.json for the same ten, plus
    # TAIR12, which production has no tab for.

    # The ".1"/".5"/".10" suffix the broken build appended to antigen names.
    # Matched only to report it - see #load_from_file.
    BROKEN_BUILD_SUFFIX = /\.(?:#{TARGET_GENES_DISTANCES.map { |d| d[:id] }.join('|')})\z/

    # cell_list's "no colo data for this antigen" marker. Splitting it on ","
    # yields ["-"], which is how a literal "-" reached the /colo picker as if
    # it were a cell-type class.
    NO_CELL_TYPES = '-'

    module_function

    def target_genes_distances
      TARGET_GENES_DISTANCES
    end

    # Genome tab strip for /colo: the full registry, filtered down to the
    # genomes that actually have colocalization data, in config/genomes.yml
    # order. Derived rather than listed - a genome is offered exactly when at
    # least one of its rows names a cell-type class. TAIR12 has 77 rows and
    # all of them are "-", matching the archive having no colo/ directory for
    # it, so it is correctly absent.
    def genomes_with_colo
      ids = dataset.exclude(cell_list: NO_CELL_TYPES)
                   .exclude(cell_list: nil)
                   .distinct
                   .select_map(:genome)
      ChipAtlas::Experiment.genomes.select { |id, _| ids.include?(id) }
    end

    def dataset
      DB[:analyses]
    end

    # antigen -> cell-type classes, and the reverse. Rows whose cell_list is
    # the "-" marker are skipped outright: they have no colo results, and
    # `"-".split(",")` gives ["-"], which is how a literal "-" ended up
    # offered as a cell-type class in the picker (and still reaches direct
    # /api/colo_index consumers). 567 rows carry it in the 2026-09-22 build,
    # so this is the difference between a correct index and a visibly wrong
    # one, not a tidy-up.
    def colo_result_by_genome(genome)
      result = { genome => { track: {}, cell_type: {} } }

      dataset.where(genome: genome).exclude(cell_list: NO_CELL_TYPES).each do |row|
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

    # genome -> antigen names with precomputed Target Genes data, i.e. the
    # rows whose third column is "+". The names are used verbatim to build
    # <genome>/target/<antigen>.<distance>.tsv, so they must stay exactly as
    # the file spells them.
    #
    # This used to exclude rows with a NULL `distance` and then backfill any
    # genome it found nothing for from a vendored snapshot of production's
    # index. Both existed only because of the broken 2026-09 build (see the
    # note at the top of this file) and both are gone: the flag column is the
    # answer, for every genome including TAIR12, which the snapshot never
    # covered.
    def target_genes_result
      result = {}
      dataset.where(target_genes: true).each do |row|
        genome = row[:genome]
        result[genome] ||= []
        result[genome] << row[:track]
      end
      result.each_value(&:uniq!)
      result
    end

    # Returns { total:, broken_build_rows: }.
    #
    # broken_build_rows counts antigen names ending in a TARGET_GENES_DISTANCES
    # id, which is the signature of the 2026-09 build described at the top of
    # this file. Those rows are still stored verbatim - nothing about the
    # source file is thrown away here - but the count is surfaced by
    # lib/tasks/metadata.rake so a bad upstream build announces itself at load
    # time. It is expected to be 0. It was 8,345 of 8,345 in September, and
    # nothing said so: the app loaded it, the site looked like it worked, and
    # a month of reasoning was built on the wrong shape. Same failure mode
    # task A3 closed for experiments/experiments_fts, one table over.
    #
    # `wdr-5.1` (ce10/ce11) is the only real antigen name whose trailing
    # segment could ever match, and upstream currently spells it `wdr-5` -
    # as do production's own colo and Target Genes indexes - so a nonzero
    # count today means the suffix is back, not a false positive. If that
    # name is ever corrected upstream this counter reports 2, which is a
    # cheap thing to read past and worth the check it buys.
    def load_from_file(table_path)
      timestamp = Time.now
      total = 0
      broken_build_rows = 0
      batch_size = 5_000

      DB.transaction do
        records = []

        File.foreach(table_path, encoding: 'UTF-8') do |line_n|
          cols = line_n.chomp.split("\t")
          genome = cols[3]
          next unless ChipAtlas::Experiment.genomes.key?(genome)

          track = cols[0]
          broken_build_rows += 1 if track.match?(BROKEN_BUILD_SUFFIX)

          records << {
            track:        track,
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
      { total: total, broken_build_rows: broken_build_rows }
    end
  end
end
