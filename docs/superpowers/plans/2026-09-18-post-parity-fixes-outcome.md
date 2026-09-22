# Post-parity fixes — outcome and handoff

Execution record for `docs/superpowers/plans/2026-09-18-post-parity-fixes.md`.
Range `0c66277..HEAD` on `sengu`. The full ledger, including every dispatch and
review, is in `2026-09-18-post-parity-fixes-ledger.md` beside this file.

**Not pushed, not merged.** The branch is local.

## State

15 of 16 tasks done. B4 (the Colocalization index) was held back by the project
owner because it is blocked on a question out with a collaborator.

```
Ruby suite      215 runs / 0 failures   (was 104 at 0c66277)
Frontend suite   74 runs / 0 failures   (did not exist at 0c66277)
tsc --noEmit    exit 0, base + test configs
ui-checklist    34/34
```

## What the four faults turned out to be

1. **Result endpoints requested a file format that has never existed.** The app
   asked for `.json`; the data server publishes `.tsv` and `.html` only. Fixed by
   parsing the TSV that exists (owner's choice, D4).
2. ~~**`analysisList.tab` was misread as a Colo index.**~~ **This finding was
   wrong — corrected 2026-09-22.** It was read off a single broken build of the
   file, the 2026-09-09/13 one this project happened to download, and does not
   describe the file. See "What `analysisList.tab` actually is" below.
3. **The job payload used field names WABI does not know.** No translation layer
   existed. The frontend now emits WABI's own vocabulary; the server adds the
   operational fields.
4. **`TAIR10` should have been `TAIR12`.** 21,836 A. thaliana experiments were
   dropped at load.

## Decisions taken on the owner's behalf

Full reasoning and cost-if-wrong for each is in the ledger. The three that were
put to the owner (18, 20, 22) were all confirmed as shipped on 2026-09-19; no
rulings were overturned.

| # | Ruling | Why it may want review |
|---|---|---|
| 1 | B5 ships without B4; verified via the API | **Was factually wrong** — see Ruling 22 |
| 2 | TAIR12 kept off `/colo` by an allowlist + TODO | replaced by B4's derived check |
| 3 | C2 proceeds: server supplies the operational fields | technically a thin translation layer, against D7's letter |
| 4 | Per-job-type availability is a constant in `ComputeRouter`, not config | |
| 5 | A2 verifies TAIR12 on a slice, not a full rebuild | |
| 6, 9, 12, 14, 19 | Folded specific Minors into fix rounds instead of deferring | each overrides the default that Minors wait |
| 7 | Pin `--network none` in `test.sh` | **half-executed** — CI had no isolation until the final wave |
| 8 | "One row set, not one file" — corrected my own plan defect | also silently changed A3's stated Verify criterion |
| 10 | Vendored `target_genes_analysis.json` snapshot as the interim human index | delete when upstream lands |
| 11, 15 | Hardened two inferred data contracts into verified ones | |
| 13 | One re-review across two fix rounds | |
| 16, 17 | Two more defects in my own brief text, corrected mid-flight | |
| 18 | 502 = backend rejected, 503 = no backend serves this type | **confirmed by owner 2026-09-19** |
| 20 | Clearing datasets on experiment-type change, beyond D13's literal option | **confirmed by owner 2026-09-19** |
| 21 | Final review scoped to this plan, not the whole branch | |
| 22 | Gate `/colo` behind the honest-unavailable state until B4 | **confirmed by owner 2026-09-19** |

## What `analysisList.tab` actually is — corrected 2026-09-22

The file is a **combined index**, and has had the same four-column shape since
2015: `antigen`, `cell_list`, `target_genes_flag`, `genome`. `cell_list` is the
**Colocalization** index — the cell types that antigen has colo results for —
and the third column flags whether it also has Target Genes output. There is no
distance dimension in it and there never was.

The 2026-09-09/13 build this project downloaded was broken in three separate
ways at once, which is what produced fault 2:

| | 2015 copies (x3) | 2026-09-13 | 2026-09-22 |
|---|---|---|---|
| rows | 1,077 | 8,345 | 6,328 |
| antigen field | bare | `antigen.1` / `.5` / `.10` | bare |
| `cell_list` | populated | **every row `-`** | populated |
| human rows | hg19 583 | **0** | hg19 1,768 / hg38 1,767 |

Blanking `cell_list` destroyed the colo index; the `.N` suffix then made the
file look like a Target Genes (TF, distance) enumeration, which it is not. The
original reading was the right one. Evidence: three independent 2015 copies at
`Dropbox/00_Research/Archive/2015-2016/peakjohn/{20150520,20150522,20150623}`,
all in the 2026-09-22 shape, and the upstream maintainer's own account that the
distance was never in the file.

**The 2026-09-22 build reproduces both of production's index endpoints exactly**,
checked field by field:

- `cell_list` vs `/data/colo_analysis.json?genome=…`: identical for all ten
  genomes production serves — 6,251 antigens, every key and every cell-type
  list.
- rows flagged `+` vs `/data/target_genes_analysis.json` (the vendored
  2026-09-19 snapshot): identical for the same ten genomes, and it additionally
  covers TAIR12 (77 antigens), which production has no tab for.

So B4's open question is answered by the data: the regenerated upstream file is
the source, for both indexes, and the vendored snapshot is redundant.

## What B4 needs, given the above
- **`Analysis.colo_result_by_genome` (`lib/models/analysis.rb`) still splits a
  `cell_list` of `"-"` into `["-"]` rather than `[]`.** This is why the picker
  offered a literal `-`. The `/colo` gate (Ruling 22) hides the human-facing
  symptom but **`/api/colo_index` still returns the bogus entry to direct API
  consumers.** B4 owns the real fix. Against the 2026-09-22 file this stops
  being theoretical: **567 rows carry `-`** (hg19 125, hg38 114, mm10 105,
  mm9 103, sacCer3 25, dm6 8, dm3 7, TAIR12 77, ce10/ce11/rn6 1 each).
- **The `distance` column, `split_track_and_distance` and
  `target_genes_result`'s `.exclude(distance: nil)` were all built to fit the
  broken build** and have nothing to read in the restored file: every row now
  resolves to `distance` NULL, so `target_genes_result` returns nothing and
  silently falls through to the vendored snapshot for every genome — with
  TAIR12, absent from that snapshot, going empty. They come out with B4, along
  with `DEFAULT_HUMAN_SNAPSHOT_PATH` and the snapshot file itself. The distance
  dimension stays in the **UI** (`TARGET_GENES_DISTANCES`) and in the filenames
  (`CTCF.1.tsv`, `.5`, `.10` all resolve); it was simply never in this index.
- **`Analysis.GENOMES_WITH_COLO`'s hardcoded allowlist can now be derived**, as
  its TODO asks: the genomes with at least one non-`-` `cell_list` are exactly
  hg38, mm10, rn6, dm6, ce11, sacCer3 among those this app offers. TAIR12's 77
  rows are all `-`, matching the archive having no `colo/` directory for it.
- **`wdr-5` (ce10, ce11) resolves no Target Genes file** — the real ones are
  `wdr-5.1.{1,5,10}.tsv`, after the C. elegans gene `wdr-5.1`. Not a regression
  in this build: production's own colo and target-genes indexes both say
  `wdr-5` too, so its Target Genes page has the same dead entry. Upstream's to
  fix, and worth reporting; one row per genome.
- `Analysis.genomes_with_colo` is a hardcoded allowlist with a TODO pointing here.
- Re-enabling the `/colo` picker is one line: `COLO_PICKER_UNAVAILABLE` in
  `frontend/pages/colo.ts`.
- `database.sqlite.rebuild` was generated before the `distance` migration —
  **regenerate any rebuilt database after all migrations**, do not reuse it.

## Deferred, with reasons

- `BedExtensionResolver` cache/prober not synchronised under threaded Puma —
  worst case is a duplicate probe against an idempotent cache.
- Six byte-identical helpers duplicated across the two matrix pages — deliberate
  (per-page esbuild entry points); extract when a third matrix page appears.
- ~~Colo's Average column uncoloured~~ — **done 2026-09-19**, owner approved.
  The formula was recovered from production's own rendered HTML: the Average is a
  mean of 0-9 concordance values, mapped onto the same 0-1000 ramp the STRING
  column uses, with the ramp starting **blue at 0** (unlike STRING, which reserves
  0 for "no data"). Verified against the shipped code: 999 of production's 1,000
  rows exact, all 1,000 within +/-1, the one exception a float artifact at
  average 2.4. See `2026-09-19-followups-ledger.md`.
- No row pagination on the colo matrix — measured fine at 3,862 rows
  (forced layout 1 ms, 2 MB heap).
- ~~No server-side gene search on Target Genes~~ — **done 2026-09-19**, owner
  approved. `/api/target_genes` now takes a `q` filter applied before sort and
  slice, so paging walks the matches and `total` is the filtered count. Verified
  live: `Zbtb16` sits at unfiltered rank 9000 (page 91 of 135) and comes back on
  page 1. Production has no equivalent — its own page caps at ~1,000 rows.
- `measure-target-genes-overflow.mjs` needs a live server and hardcodes
  `mm10/Stat3/1` — it now asserts its own precondition, which was the part
  that mattered.
- The rake orphan assertion in `clean_old_genomes.rake` runs after commit and
  VACUUM: it detects, it does not prevent.
- No jsdom anywhere, so DOM wiring is covered by pure-function tests plus manual
  verification — a project-wide convention, not introduced here.
- ~~**Q3: TAIR genome size and coding-gene count**~~ — **resolved 2026-09-22**,
  both derived from the assembly ChIP-Atlas itself publishes at
  `chip-atlas.dbcls.jp/data/genome/TAIR12/`, which the owner pointed to. They
  were the last two gaps in the Enrichment Analysis estimate: the sequence-motif
  branch needs a genome size, the "RefSeq coding genes" branch needs a gene
  count, and production's tables have no TAIR entry because it has no TAIR tab.

  - **Genome size 142,481,245 bp** — the sum of all five sequences in
    `TAIR12.fa.gz.fai`. The basis was verified against production rather than
    assumed: summing the chrom.sizes ChIP-Atlas publishes reproduces
    production's `genomesize` entry **to the byte for rn6 and sacCer3**, the two
    genomes whose entry corresponds to an assembly still measurable today. The
    other four differ only because production's figures are per-species and it
    kept the older assembly's total — its hg38 entry is hg19's, its dm6 entry is
    dm3's, its mm10 entry mm9's, its ce11 entry ce10's. Those are left alone.

  - **Coding genes 26,867** — distinct AGI locus codes parenting an mRNA feature
    in `TAIR12.genes.gff3.gz`, agreed on by two independent passes (mRNA Parent
    and CDS Parent) and distributed across Chr1-5 as 7,029 / 4,159 / 5,329 /
    4,097 / 6,253. This could not come from production's basis on any reading:
    Arabidopsis has no RefSeq annotation, so the gene set an analysis runs
    against is the one ChIP-Atlas publishes. Production's own `numGenes` figures
    stay copied as given — no counting rule over the RefSeq Curated tables
    published today reproduces any of them (current counts run a few percent
    above production's for five genomes and well below it for rn6), so their
    derivation is not recoverable and was not guessed at.

  Precision was checked before relying on it: at TAIR12's largest numRef a 12%
  error in the gene count moves the estimate by one minute.

## Six "passes while testing nothing" defects found during this run

Recorded because the pattern recurred far more than expected:

1. Adding a probe to `bed_url` made three **pre-existing** tests call the
   production data server; they passed because their assertions never looked at
   the extension.
2. The overflow regression script had no precondition, so it would have passed if
   the table stopped being wide enough to overflow.
3. `test-frontend.sh`'s glob matched zero files once a test lived outside
   `frontend/pages/` — green while running nothing.
4. …and after that was "fixed", an empty match still exited 0, because
   `node --test` with no arguments reports success.
5. `tsconfig.json` silently stopped type-checking ~1,100 lines of test code.
6. `--network none` was pinned locally but never in CI, and `DataProxy` had no
   test guard — so two tests really did reach `chip-atlas.dbcls.jp` on every CI
   run, passing only because upstream returns 404.
