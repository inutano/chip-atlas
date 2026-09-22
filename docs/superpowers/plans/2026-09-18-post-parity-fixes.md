# ChIP-Atlas sengu — post-parity fix instructions

**Sources of truth, in precedence order**

1. Tazro's 17 decisions, recorded 2026-09-18 (artifact `5f380562` collection `decisions`).
2. `chip-atlas_update_260915.pdf` — the pipeline update from the data side, 2026-09-15.
3. The parity report (`funcparity/final.html`) and the five per-function reports.

**Branch:** `sengu`, currently at `0c66277`. Not pushed.

---

## Global constraints

- Ruby 4.0.5, Sinatra + Sequel + SQLite/FTS5. Frontend is TypeScript compiled by
  esbuild, strict mode, no runtime dependencies, no external CSS/JS.
- `bash script/dev/test.sh` must stay green (104 runs at time of writing).
  `npx tsc --noEmit -p frontend/tsconfig.json` must exit 0.
- `script/dev/ui-checklist.sh` must not regress below 34/34.
- Do not edit `script/dev/parity-markers.txt` unless a task here says to.
- The data server is `https://chip-atlas.dbcls.jp/data`. Never submit a real
  analysis job to WABI from a test or a dev run.

---

## Open questions

Q1, Q3 and Q4 were answered by Tazro on 2026-09-18 and are recorded here as
settled. Q2 is still out with the collaborator; Task B4 proceeds on the stated
assumption and is built so the answer can be swapped in without rework.

### Q1 — CUT&Tag — **ANSWERED: hide from the menu**

CUT&Tag is being analysed, but it has been folded into ChIP for menu purposes, so
it gets no menu entry of its own. Remove both `CUT&Tag` and `CUT&RUN` from
`EXPERIMENT_TYPES`.

This is clean, because neither label exists in the data — they are only in the
app's hardcoded list. The ten track classes actually present are:

```
ATAC-Seq 97634   Histone 88496   TFs and others 66602   Bisulfite-Seq 65406
Input control 37701   Unclassified 36360   No description 23857
RNA polymerase 9548   DNase-seq 6495   Annotation tracks 541
```

When CUT&Tag data lands it will arrive classified as Histone / TFs and others,
so nothing downstream needs to change. `Unclassified` and `No description` are
deliberately absent from the menu on both the old and new sites — leave them out.

### Q2 — Who produces the Colocalization index? — **PENDING (collaborator)**

`analysisList.tab` is **not** a colo index — see the next section. Nothing in the
current pipeline tells the app which (antigen, cell-type-class) pairs have a colo
file, so decision D5 does not fix Colocalization on its own.

**Proceed on:** Task B4 uses production's `/data/colo_analysis.json?genome=…`
behind a swappable loader, so an upstream file can replace it later without
touching the API or the UI. Do not design the API around the interim source's
shape.

### Q3 — `assembled/` gzip — **ANSWERED: everything eventually, progressively**

Every genome will move to `.bed.gz`, but genome by genome as each is reprocessed.
Today TAIR12 is gzipped and hg38 is not (verified both ways). So the set is
mid-migration and will keep changing under the running app.

That makes per-genome resolution the **permanent design**, not a stopgap: resolve
`.bed` then `.bed.gz` at request time and cache the result per (genome, filename)
with a bounded TTL, so a genome that gets reprocessed is picked up without a
deploy. Do not read the extension from config — it would need editing every time
a genome is converted.

### Q4 — Human in the regenerated `analysisList.tab` — **ANSWERED: it should be there**

Human is expected in the file; its absence is a bug to be investigated upstream.
Until that lands, Task B1 uses the interim index source so human Target Genes
works now.

Lead for whoever investigates: the data is not missing, only the index rows.
`hg38/target/STAT3.1.tsv`, `hg38/target/GATA1.1.tsv` and `hg19/target/STAT3.1.tsv`
all return 200. So the generator is skipping human rather than finding nothing.
Nothing in this repo generates the file — `lib/tasks/metadata.rake` only downloads
it — so the fix is entirely on the pipeline side. One hypothesis worth ruling out
first: hg38 alone would add ~5,300 rows (1,766 antigens × 3 distances) to a file
that is currently 8,345 rows, so a size, timeout or per-genome loop cutoff would
show exactly this symptom.

## What `analysisList.tab` actually is

> **Superseded 2026-09-22 — this whole section is wrong.** It reasons from the
> 2026-09-09/13 build of the file, which was broken: it had blanked `cell_list`
> to `-` on every row, dropped all human rows, and appended a `.1`/`.5`/`.10`
> suffix to the antigen name. The file is a **combined colo + Target Genes**
> index and has had the same shape since 2015, with no distance dimension at
> any point. The original parity report's reading was right and the
> "correction" below was not. See "What `analysisList.tab` actually is —
> corrected 2026-09-22" in `2026-09-18-post-parity-fixes-outcome.md`, which
> carries the evidence and what it means for B4. Kept as written because the
> ledger's rulings refer to it.

This corrects the parity report, which described the file as "degraded". It is
not degraded — it has been repurposed, and the report's Fault 2 overstated the
damage. Each row is one **(TF, distance)** pair for **Target Genes only**:

```
AGL20.1   -   +   TAIR12      →  https://…/data/TAIR12/target/AGL20.1.tsv   200
Acaa2.10  -   +   mm10        →  https://…/data/mm10/target/Acaa2.10.tsv    200
```

The `.1`/`.5`/`.10` suffix is the TSS distance in kb and **matches the real
filenames exactly**. The cell-list column is `-` on all 8,345 rows and the
target-genes flag is `+` on all of them because that is the file's whole purpose.

Consequences:

- **Target Genes** needs the suffix split into `track` + `distance` at load. No
  upstream change is required for the genomes the file covers.
- **Colocalization** has no index source at all. Colo data files exist
  (`mm10/colo/Actb.Embryonic_fibroblast.tsv` → 200) but nothing enumerates the
  valid pairs. `Actb.-.tsv` → 404, which is why every colo query fails. See Q2.
- Human is absent from the index but present on disk, for both functions. See Q4.

---

## Task order

A1 → A2 → A3 may run in parallel with C1 → C2. B tasks depend on A1. D tasks are
independent. Do not start B4/B5 before Q2 is answered or its assumption accepted.

---

## Group A — data layer

### Task A1 — Genome registry from config  *(D1, D2)*

**Files:** `lib/models/experiment.rb`, new `config/genomes.yml`,
`lib/tasks/metadata.rake`, `test/`

Legacy builds (hg19, mm9, dm3, ce10) stay dropped — D1. Replace the hardcoded
`GENOMES` hash with a config file read at boot and at DB build time, so the
supported set changes without a code edit.

```yaml
# config/genomes.yml — order here is the order shown in every genome tab strip
genomes:
  - id: hg38
    label: "H. sapiens (hg38)"
  - id: mm10
    label: "M. musculus (mm10)"
  - id: rn6
    label: "R. norvegicus (rn6)"
  - id: dm6
    label: "D. melanogaster (dm6)"
  - id: ce11
    label: "C. elegans (ce11)"
  - id: sacCer3
    label: "S. cerevisiae (sacCer3)"
  - id: TAIR12
    label: "A. thaliana (TAIR12)"
```

`GENOMES` becomes a memoized read of this file; `GENOME_ORDER` derives from it.
Every current consumer (`list_of_genome`, `/api/genomes`, the FTS loader's
`SUPPORTED_GENOMES`, `Analysis.load_from_file`) must go through it — grep for
`GENOMES` and convert all of them.

**Verify:** `/api/genomes` returns the seven ids in file order; adding a bogus id
to the YAML makes it appear in `/api/genomes` without a code change; tests green.

### Task A2 — TAIR12 end to end  *(D2, PDF)*

**Files:** `config/genomes.yml` (done in A1), `lib/services/location_service.rb`,
`lib/models/bedfile.rb`

The metadata carries 21,836 A. thaliana experiments under `TAIR12`; the app keyed
them `TAIR10`, so all of them were dropped at load. A1 fixes the key. This task
makes the rest of the genome work.

1. Rebuild the DB and confirm the 21,836 rows load and are searchable.
2. `LocationService#bed_url` must resolve for TAIR12. Per Q3 the archive is
   mid-migration to gzip, genome by genome, so resolve at request time: try
   `.bed`, fall back to `.bed.gz`, and cache the answer per (genome, filename)
   with a bounded TTL. A genome that gets reprocessed must start working without
   a deploy, so do not put the extension in config and do not hardcode it.
3. Confirm Target Genes works for TAIR12: `TAIR12/target/AGL20.1.tsv` → 200.
4. **Colocalization has no TAIR12 data** — the PDF's directory tree has no
   `colo/` under TAIR12 and `TAIR12/colo/AGL20.-.tsv` → 404. The genome must not
   offer Colo. Make the Colo genome strip derive from which genomes have a colo
   index rather than from the global genome list.
5. `correlation_tsv_url` already builds `<genome>__x__<track>__x__<cell>.tsv`,
   which matches the PDF's `TAIR12__x__<抗原>__x__<細胞>.tsv`. No change needed —
   confirm with one live request, do not rewrite.

**Verify:** TAIR12 tab populated on Peak Browser, Enrichment Analysis, Search and
Target Genes; absent on Colo; IGV and BED download both resolve to a 200 URL.

### Task A3 — One source for both stores  *(D3)*

**Files:** `lib/models/experiment.rb`, `lib/models/experiment_search.rb`,
`lib/tasks/metadata.rake`

`experiments` (432,640) and `experiments_fts` (432,318) disagree in both
directions: 219 ids exist only in the index and 404 on `/view`; 541 annotation
tracks exist only in the table and cannot be searched.

1. Load both stores from `experimentList.tab` in one pass, applying the same
   genome filter from `config/genomes.yml`.
2. Annotation tracks stay out of the search index — that is the existing
   behaviour and it is correct, but write it as an explicit, commented rule with
   a test, not an accident of two loaders.
3. Add a post-load consistency assertion to the rake task: every FTS row must
   have an `experiments` row. Fail the build loudly rather than shipping orphans.

**Verify:** the orphan query returns 0; `/api/stats` and the search total differ
by exactly the annotation-track count, and a test asserts that relationship.

---

## Group B — Target Genes and Colocalization

### Task B1 — Target Genes index  *(D5, Q4)*

**Files:** `lib/models/analysis.rb`, `routes/api.rb`, `frontend/pages/target-genes.ts`

Split `<TF>.<kb>` at load: store `track` and `distance` as separate columns.
`/api/target_genes_index` then returns bare antigen names per genome, matching
its own OpenAPI spec, and the UI stops sending `Stat3.1` as `track`.

Source the index behind one swappable method. Per Q4 human belongs in the file
and its absence is an upstream bug, so this indirection is temporary — but keep
it, because the switch-over will happen while the app is running:

- **now:** production's `/data/target_genes_analysis.json` (10 genomes, hg38 =
  1,766 clean names) — this is what makes human Target Genes work today.
- **later:** the regenerated `analysisList.tab`, once it covers human.

**Verify:** typing `STAT3` on hg38 offers exactly one suggestion; the request is
`track=STAT3&distance=1`; the suffix appears nowhere in the UI.

### Task B2 — Target Genes results from TSV  *(D4)*

**Files:** `lib/services/data_proxy.rb`, new `lib/services/target_genes_tsv.rb`,
`routes/api.rb`

Stop requesting `.json` — it has never existed. Parse the `.tsv` that does.

```
mm10/target/Stat3.1.tsv   13,460 rows × 134 cols   4.1 MB
col 1        Target_genes           gene symbol
col 2        Stat3|Average          mean score for the query TF
cols 3..n-1  SRX361677|Astrocytes   one column per experiment
col n        STRING                 STRING interaction score
```

4.1 MB × 134 columns is too large to hand to the browser. `/api/target_genes`
must sort and slice server-side: accept `sort` (default the `|Average` column),
`order`, `offset`, `limit`, and return the column headers separately from the
rows. Cache the parsed matrix per (genome, track, distance) with a short TTL —
re-downloading 4 MB per page click is not acceptable.

**Verify:** `/api/target_genes?genome=mm10&track=Stat3&distance=1` returns 200
with headers and the first page; hg38 STAT3 likewise; a missing combination
returns 404 with a message distinguishable from a broken one.

### Task B3 — Target Genes result UI  *(D11)*

**Files:** `views/target_genes_result.erb`, `frontend/pages/target-genes-result.ts`

Reproduce production's tree/heatmap rather than a flat table. Carry over the
affordances production has: in-place distance switching (±1 / ±5 / ±10 kb), the
score colour legend, the TSV download link, and outbound `/view?id=SRX…` links.
Paginate against B2's server-side slice; do not attempt to render 13,460 rows.

### Task B4 — Colocalization index  *(D5, Q2)*

**Files:** `lib/models/analysis.rb`, `routes/api.rb`

Colo needs an index that does not currently exist anywhere in the pipeline. Build
it behind the same swappable interface as B1, sourced for now from production's
`/data/colo_analysis.json?genome=…`, which returns the correct shape:

```json
{"hg38": {"antigen": {"AATF": ["Others"], "ADNP": ["Blood", "Liver"], …}}}
```

Both directions must work: antigen → cell classes, and cell class → antigens
(the reverse index currently collapses to a single literal `"-"`). Genomes with
no colo index — TAIR12 today — must not appear on the page.

**Verify:** `/api/colo_index?genome=hg38` is non-empty; the reverse direction
offers 21 real cell-type classes; suggestions carry no `.1`/`.5`/`.10` suffix.

### Task B5 — Colocalization results and matrix  *(D4, D6)*

**Files:** new `lib/services/colo_tsv.rb`, `routes/api.rb`,
`views/colo_result.erb`, `frontend/pages/colo-result.ts`

Parse the TSV and reproduce production's matrix — D6 chose the matrix, not the
ranked list, so the current `Rank / Score / Shared Bins` schema is replaced.

```
hg38/colo/STAT3.Blood.tsv   3,863 rows × 21 cols   263 KB
col 1        Experiment                        SRX347427
col 2        Cell_subclass                     SU-DHL-4
col 3        Protein                           STAT3
col 4        STAT3|Average                     3.866667
cols 5..n-1  SRX150636|GM12878                 per-experiment concordance
col n        STRING                            STRING score
```

Keep the peak-intensity concordance colour coding and the STRING column with
production's legend. 263 KB is small enough to send whole; Target Genes' size
problem does not apply here. Keep the existing TSV and GML download buttons —
both proxies already work when given production's naming.

**Verify:** `STAT3` / `Blood` on hg38 renders 3,862 data rows with the legend;
TSV and GML downloads return the byte counts the data server reports.

---

## Group C — job submission

### Task C1 — WABI field names in the frontend  *(D7, D8, D10)*

**Files:** `frontend/pages/enrichment-analysis.ts`, `frontend/pages/diff-analysis.ts`,
`views/enrichment_analysis.erb`, `openapi.yaml`, `test/`

D7 chose no translation layer: the frontend emits WABI's own names. Rename every
field it builds.

| now | becomes |
|---|---|
| `track_class` | `antigenClass` |
| `cell_type_class` | `cellClass` |
| `qval` | `threshold` |
| `dataA_type` / `dataA` | `typeA` / `bedAFile` |
| `dataB_type` / `dataB` | `typeB` / `bedBFile` |
| `permutations` | `permTime` |
| `dataA_title` / `dataB_title` | `descriptionA` / `descriptionB` |

Two field-level changes go with it:

- **Threshold values (D10):** send production's `50 / 100 / 200 / 500` as
  `threshold`, not the `05 / 10 / 20 / 50` codes. The displayed labels are
  already correct; only the option `value` attributes change. Keep the codes
  wherever they name files (`allPeaks_light.<genome>.{05,10,20,50}`) — these are
  two different encodings that happen to share digits, and conflating them is
  the single most likely way to ship a wrong answer. Add a test asserting the
  submitted value for each of the four labels.
- **Distance from TSS (D8):** restore `distanceUp` and `distanceDown` as editable
  number inputs defaulting to 5000, shown in gene-list and gene-count-table
  modes, sent on every submission. Restore the `tss` / `disttss` help topics.

Update `openapi.yaml` to match and fix the tests that assert the old names.

### Task C2 — Server supplies the operational fields  *(D7, needs sign-off)*

**Files:** `lib/services/wabi_service.rb`, `routes/jobs.rb`

`address`, `format`, `result` and `sbatchOptions` are operational, not user
input. Have `WabiService` merge them in rather than making the frontend carry
them. This is technically a thin translation layer, which D7 argued against —
flagged in the reply to Tazro; proceed this way unless he says otherwise.

### Task C3 — Honest availability  *(D12)*

**Files:** `lib/services/compute_router.rb`, `routes/jobs.rb`, `routes/health.rb`

`ComputeRouter.available_backend` ignores `job_type` and routes everything to
WABI, so `/status` reports `"diff_analysis":"ok"` while submission fails. Add a
per-job-type check driven by config, and separate the two failure modes: a
backend that is down, and a submission the backend rejected. Today both collapse
into `{"error":"No compute backend available"}`, which is wrong in the second
case and misleads whoever is debugging it.

**Verify:** with diff analysis marked unavailable, `/status` says so, the UI shows
an unavailable state rather than a form that cannot submit, and a rejected
submission returns a distinct message.

### Task C4 — Per-genome form state in Diff Analysis  *(D13)*

**Files:** `views/diff_analysis.erb`, `frontend/pages/diff-analysis.ts`

One set of inputs is shared across all seven genome tabs, so IDs typed under hg38
stay in the box when the user switches to mm10 and can be submitted against the
wrong genome with no warning. Hold state per genome, as production does
structurally. Keep the title fields as they are — production resets them on every
tab click, which loses typed titles; the current behaviour is better.

### Task C5 — Stop Dataset B reverting silently  *(adjacent to D9)*

**Files:** `frontend/pages/enrichment-analysis.ts`

D9 keeps the rule that Dataset B's RefSeq and user-gene-list options are only
available when Dataset A is a gene list. Inside that rule there is a bug:
switching Dataset A back to BED silently resets Dataset B to Random permutation.
Preserve the previous Dataset B selection and restore it when the gate reopens.

---

## Group D — search and small parity items

### Task D1 — Show what the search matched  *(D14)*

**Files:** `views/search.erb`, `frontend/pages/search.ts`, `routes/api.rb`

Search matches Title and Attributes but shows neither, so a row can appear with
no visible reason. Add both columns. Attributes are long — truncate with an
expand affordance rather than letting the table blow out. Keep the current wide
matching; do not restore the Simple/Detailed tabs.

### Task D2 — Enrichment experiment-type list  *(D15, Q1)*

**Files:** `lib/models/experiment.rb`, `frontend/pages/enrichment-analysis.ts`

Exclude `Annotation tracks` from the Enrichment Analysis experiment-type list,
reproducing production's explicit `if (label != "Annotation tracks")`. **Keep
them in Peak Browser**, where annotation tracks are a legitimate track type —
D15 is about Enrichment Analysis only.

Per Q1, remove **both** `CUT&Tag` and `CUT&RUN` from `EXPERIMENT_TYPES`. CUT&Tag
is folded into ChIP for menu purposes, and neither label exists in the data, so
this is a pure deletion with no migration. Do not add a zero-count hiding rule —
it is not needed and would also hide legitimate empty categories per genome.

### Task D3 — Links  *(D17)*

**Files:** `views/search.erb`, `frontend/pages/search.ts`

D17 chose links only. Two changes, nothing else:

- GEO IDs link to `https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=<id>` for
  any non-`-` value, `target="_blank" rel="noopener noreferrer"`.
- SRX result links open in a new tab, as production does.

Leave pagination, autocomplete matching, listbox heights and the jump-to-experiment
example value alone — D17 explicitly kept those as they are.

---

## Not in scope

Recorded so nobody re-opens them by accident:

- Legacy genome builds (hg19, mm9, dm3, ce10) — D1, deliberately dropped.
- Simple/Detailed search tabs, column sorting, the show-N-entries selector — the
  earlier scope decision stands. Copy and TSV export already exist and work.
- The Dataset B RefSeq gate itself — D9 keeps it. Only the silent revert (C5) is
  a bug.
- One-directional facet filtering — D16 keeps the bidirectional behaviour.
- The `/agents` and `/demo` routes — removed from the navbar, still serving.
