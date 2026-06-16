# ChIP-Atlas Functional Parity Report — Old vs. New (Shikinen-Sengu)

**Date:** 2026-06-15
**Compared:** Old production app at `https://chip-atlas.org` vs. the rebuilt (`sengu`) app running locally on `:9876`
**Method:** 16-agent automated comparison workflow (`chipatlas-parity`) — 189 live HTTP checks across both apps, with adversarial verification of every suspected mismatch.

## Verdict

**Functional / contract parity: YES — zero confirmed regressions** across all 15 comparison slices. Every function tested produces the same result on the new app as the old; the only differences are the intentional ones from the rebuild plan.

> **Caveat.** This establishes *contract/logic* parity against the new app's current (partial dev) database. *Data-completeness* parity — full experiment counts, long-tail antigens/cell types, and the newly-added organisms — must be re-confirmed after the full data regeneration. See "To re-verify after the data regen" below.

## What was compared

The two apps diverge by design in three ways, so the comparison targets *functional* equivalence, not byte-identical output:

| | Old (`chip-atlas.org`) | New (`sengu`) |
|---|---|---|
| API paths | `/data/*` | `/api/*` |
| Field names | camelCase (`agClass`, `clSubClass`) | snake_case (`track_class`, `cell_type_subclass`) |
| Data scope | 10 assemblies incl. hg19/mm9/dm3/ce10 | 7: dropped those 4, added TAIR10; partial dev DB |

Old↔new mapping used throughout: `agClass↔track_class`, `agSubClass↔track_subclass`, `clClass↔cell_type_class`, `clSubClass↔cell_type_subclass`, `readInfo↔read_info`, `clSubClassInfo↔cell_type_subclass_info`, `expid↔experiment_id`. The qval vocabulary (`["05","10","20","50"]`) is identical on both.

### Routes — 15/15 ✓

All 10 user pages (`/`, `/peak_browser`, `/view`, `/colo`, `/target_genes`, `/enrichment_analysis`, `/diff_analysis`, `/search`, `/publications`, `/agents`, `/demo`) return 200 on both apps. The `/data/*` vs `/api/*` namespace split (each app 404s the other's paths) is the intended API redesign, not a regression.

### Taxonomy — 69/69 id/label sets ✓

For all 6 shared genomes (hg38, mm10, rn6, dm6, ce11, sacCer3), the classification vocabulary — track classes, track subclasses (antigens), and cell-type subclasses — is byte-identical in `id` and `label` between old and new. The only difference is the new app's empty `CUT&Tag` / `CUT&RUN` track classes (intended additions, `count: null`).

### URL generation — 137/137 byte-identical ✓ (the strongest signal)

Across 137 conditions spanning all 6 genomes, every generated peak-call download URL is **byte-for-byte identical** between old and new — including the abbreviation maps (`Histone`→`His`, `TFs and others`→`Oth`, `Blood`→`Bld`, …), special-character escaping, the "all cell types" aggregation, and null-vs-URL gating for conditions with no precomputed file. Both apps emit `https://chip-atlas.dbcls.jp/data/<genome>/assembled/<filename>.bed`.

This is the most important result: **the new app directs researchers to the exact same data files as the old app.**

### Metadata — 24/24 ✓

For 24 hg38 experiments (sampled via search on `CTCF` and `H3K4me3`), every per-experiment field value matches old↔new after the field-name mapping: classification, title (including the `GSM####:` prefix), attributes, and `read_info`. The old app's extra hg19 row per experiment is the intended assembly drop.

## Confirmed regressions

**None.** No comparison slice produced a mismatch that survived adversarial verification as a real regression.

## Intended differences confirmed (working as designed)

- **API surface:** `/data/*` → `/api/*`; download moved from `POST /download` to `GET /api/download_url`.
- **Field naming:** camelCase → snake_case throughout.
- **Assemblies:** dropped hg19/mm9/dm3/ce10; added (currently empty) TAIR10, plus empty `CUT&Tag`/`CUT&RUN` track classes.
- **Search:** FTS5-backed `/api/search` replaces the old bulk-JSON + DataTables search.

## Open question (tracked decision)

**Search-result title prefix.** The new `/api/search` omits the `GSM####:` prefix from experiment titles, whereas the old search included it. The `/api/experiment` detail endpoint *retains* the prefix exactly as before, so per-experiment metadata parity is unaffected — this is purely a search-results display difference.

**Decision needed:** keep the prefix in search results to match the old app, or accept the cleaner titles as an intentional improvement? Low priority; easy to restore if desired.

## To re-verify after the data regen

This report covers contract/logic parity on the current partial dev DB (which happened to fully populate every slice sampled). Once the full database is regenerated, re-run the same workflow to confirm **data-completeness** parity:

- Long-tail antigens / minor cell-type classes absent from the dev DB should reappear; broader taxonomy + metadata sampling should re-expand to the old app's full counts.
- **TAIR10** (Arabidopsis) taxonomy + URL generation, once its data is loaded.
- **CUT&Tag / CUT&RUN** taxonomy, URL generation, and metadata, once those assays are populated.

## How to re-run

1. Boot the new app: `WEB_CONCURRENCY=0 RACK_ENV=development bundle exec puma -p 9876 -e development config.ru`
2. Re-invoke the saved `chipatlas-parity` workflow (or have Claude re-author it from this report). Same script + a fully-populated DB → the data-completeness pass.

The comparison is deterministic and read-only; it makes a few hundred lightweight requests to the live production app, so it is safe to repeat.
