# Regression Fixes after the 2026-09-23 Old-vs-New Review — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every item the 2026-09-23 review classified as `退行 (要修正)` (40 items, IDs below) and re-enable Diff Analysis job submission, restoring production (chip-atlas.org) behaviour wherever the new app diverged unintentionally.

**Architecture:** Fix shared components first (ListBox/Autocomplete selection sync, FacetFilter per-track-class rules), then each page, then Ruby services/routes, then documentation. Production behaviour is the reference; its code is available read-only at `SCRATCH/old-app/` (git `master`, identical to what chip-atlas.org serves) where `SCRATCH = /private/tmp/claude-501/-Users-inutano-repos-chip-atlas/d2f860a9-de11-4510-8b60-649b4cb4f929/scratchpad`. Every regression item's evidence is in `docs/review-2026-09-23/findings/*.md` (search the item ID, e.g. `PB-18`).

**Tech Stack:** Sinatra 4 + Sequel + SQLite (Ruby 4.0.5), ERB (erubi, `escape_html: true`), TypeScript compiled by esbuild into `public/js/*.js`, minitest + rack-test, `node --test` for frontend unit tests. No new dependencies.

**Spec:** `docs/review-2026-09-23/01-ui-changes.html` (総括 + items) and the owner's rulings of 2026-09-24: (1) Diff Analysis backend (WABI) is available again — re-enable it; (2) Diff Analysis panel headings go back to production's "2. Enter dataset A" / "3. Enter dataset B"; (3) the home page gets an automatic service-status banner instead of a hand-edited notice; (4) TAIR12 example data will be supplied by the owner later — do not generate it, but make per-mode example loading work so that placing files under `public/examples/TAIR12/` is enough; (5) the A. thaliana gene-identifier convention is unconfirmed — do not document one.

## Global Constraints

- **Do not run host-side `sqlite3` against `database.sqlite*`** — it corrupts the WAL shared memory of the running Docker instance (verified crash on 2026-09-23). Query data through the running app (`http://localhost:9292/api/...`) or inside the container (`docker exec chip-atlas-local bundle exec ruby -e '...'`). Tests use their own fixture DB (see `test/test_helper.rb`).
- **Local instance:** `http://localhost:9292` is Docker container `chip-atlas-local` bind-mounted on this working tree, `RACK_ENV=development`. ERB and `public/js` changes are live immediately (run `npm run build` after TypeScript changes). Ruby changes need `docker restart chip-atlas-local` (takes ~60-90 s; wait for `curl -sf http://localhost:9292/health`).
- **Verification commands (all must pass before every commit):** `bash script/dev/test.sh` (Ruby suite, prebuilt image `chip-atlas-test:local`), `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json`, `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.test.json`, `npm run build`, `bash script/dev/test-frontend.sh`, `bash script/dev/ui-checklist.sh` (score must stay 34/34).
- **Zero external dependencies, plain CSS + TypeScript only, no `alert()`/`confirm()` in new code** (production's alerts become inline messages in the page's existing status element, with production's wording).
- **Templates escape by default;** `<%==` only for trusted server-generated HTML.
- **Keep the existing test conventions:** frontend tests are pure-function tests of exported helpers (no jsdom) in `frontend/**/*.test.ts`; Ruby tests in `test/**/*_test.rb` with `Rack::Test`. Every behaviour change gets a test; DOM wiring gets a manual live check documented in the report.
- **Commit messages:** plain imperative subject, no prefix (repo convention), and end with the two attribution lines:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01LDsEWzb3cA5D6Ndw2YdBFr`.
- Do not modify `docs/review-2026-09-23/` or `.superpowers/`.

---

### Task 1: ListBox/Autocomplete selection sync (COLO-04, TG-09) and Colo list order (COLO-03)

**Files:**
- Modify: `frontend/components/list-box.ts`, `frontend/components/autocomplete.ts`
- Modify: `frontend/pages/colo.ts`, `frontend/pages/target-genes.ts`
- Test: `frontend/pages/colo.test.ts` (extend), create `frontend/components/autocomplete.test.ts`

**Interfaces:**
- Produces: `Autocomplete.init(input, items, onSelect, { pairedList })` now calls `onSelect(value)` whenever the paired ListBox ends up with a real selection that the page state does not know about: (a) after `Autocomplete.setItems` repopulates the list and its first row is auto-selected, (b) when the user types text that exactly equals one item (case-insensitive, trimmed) — production's `keyup` handler synced the `<select>` this way (`old-app/public/js/pj/colo.js:151-159`, `target_genes.js:152-157`).
- Produces: exported pure helper in `autocomplete.ts`: `export function exactMatch(items: string[], text: string): string | null` (returns the item whose lower-cased trimmed form equals the lower-cased trimmed text, else null).
- Produces: `ListBox.setOptions(options, selected)` returns `boolean` — `true` when it auto-selected the first row because nothing matched `selected` (so callers can tell an auto-selection from a preserved one).

Behaviour to restore (production): the first row of every list box is *really* selected on load (`old-app/public/js/pj/colo.js:107-125`, `target_genes.js:113-120`), so "pick an antigen → View" works without clicking the list, and the secondary list is re-seeded with its first row when the primary changes.

- [ ] **Step 1: Tests first.** In `frontend/components/autocomplete.test.ts` add cases for `exactMatch`: exact match returns the item as stored (`['AATF','STAT3']`, `'stat3 '` → `'STAT3'`); no match → null; empty text → null. In `frontend/pages/colo.test.ts` add: `primaryItemsFor` and `secondaryItemsFor` return arrays sorted with JavaScript's default `.sort()` (production used `options.sort()`), e.g. entry `{ track: { STAT3: ['Blood'], AATF: ['Others'] }, cell_type: { Others: ['AATF'], Blood: ['STAT3'] } }` → primary `['AATF','STAT3']`, secondary (no primary) `['Blood','Others']`. Run `bash script/dev/test-frontend.sh` and see them fail.
- [ ] **Step 2: ListBox.** Make `setOptions` return whether it auto-selected the first row. Do not fire `onChange` from `setOptions` (FacetFilter's cascade relies on `onChange` meaning a user action).
- [ ] **Step 3: Autocomplete.** In `init` (when `pairedList` is given) and in `setItems`: after populating the list box, if `listBox.value` is non-null and (`input.value` is empty or `exactMatch(items, input.value) === listBox.value`), call `onSelect(listBox.value)`. Add an `input` listener: `const m = exactMatch(inst.items, input.value); if (m && inst.listBox) { inst.listBox.value = m; onSelect(m) }`. Keep the dropdown behaviour unchanged. `onSelect` must never be called for an empty list.
- [ ] **Step 4: Pages.** `colo.ts`: sort in `primaryItemsFor` / `secondaryItemsFor` (`[...keys].sort()`); make sure the primary `onSelect` (which clears the secondary and calls `refreshSecondary()`) still works when triggered by auto-selection — after `refreshSecondary()` the secondary's first row is auto-selected and `currentSecondary` is set via the new callback. Guard against redundant work: if `onSelect` for the primary receives the value already in `currentPrimary`, do nothing. `target-genes.ts`: `currentTrack` is now set by the auto-selection; remove nothing else. Verify no infinite loop (setItems → onSelect → setItems of the *other* list only).
- [ ] **Step 5: Live check** (after `npm run build`): on `/colo` and `/target_genes`, without touching any list, click "View …" → navigates to the result page with the first antigen (hg38: AATF / Others). Select STAT3 in the Colo primary list → secondary list shows STAT3's cell types sorted, first one selected, View works. Type `stat3` in the input (no Enter) → View uses STAT3. Record the checks in the report.
- [ ] **Step 6: Run all verification commands; commit** (`Select the first list-box row for real on Colo and Target Genes; sort Colo lists`).

---

### Task 2: FacetFilter per-track-class rules (PB-18, PB-19 frontend, PB-14, PB-11)

**Files:**
- Modify: `frontend/components/facet-filter.ts`
- Test: `frontend/components/facet-filter.test.ts`

**Interfaces:**
- Produces (exported, pure, tested): `qvalOptionsFor(trackClass: string, apiValues: string[]): { id: string, label: string }[]` — `'Bisulfite-Seq'` → `[{ id: 'bs', label: 'NA' }]`; `'Annotation tracks'` → `[{ id: 'anno', label: 'NA' }]`; anything else → `apiValues.map(v => ({ id: v, label: qvalLabel(v) }))`.
- Produces (exported, pure, tested): `trackSubclassItemsFor(trackClass: string, apiItems: ClassificationItem[]): ClassificationItem[] | 'NA'`: for `'Input control' | 'ATAC-Seq' | 'DNase-seq' | 'Bisulfite-Seq'` → `[{ id: '-', label: 'NA', count: null }]` **without calling the API** (production `old-app/public/js/pj/peak_browser.js:98-109`); for `'Annotation tracks'` → `apiItems` with the `'-'` ("All") entry removed (production lists only the annotations, first one selected: `peak_browser.js:127-138`); otherwise `apiItems` unchanged. (Return the array; drop the `'NA'` literal from the signature if a plain array is cleaner.)
- Produces: `FacetCondition.qval` may now be `'bs'` or `'anno'`; `facet-change` events carry `detail: { facet: FacetKey | 'init' }` (which control changed), so pages can tell which side of a pair the user touched (Task 3 needs it).
- Consumes: nothing new.

- [ ] **Step 1: Tests** for the two pure helpers (all branches above, incl. `'DNase-seq'` casing exactly as the API returns it; check the actual id via `curl 'http://localhost:9292/api/track_classes'` and use the real ids). Run, see failures.
- [ ] **Step 2: Implement** in `facet-filter.ts`: `loadTrackSubclasses` uses `trackSubclassItemsFor` (skip the fetch for the four NA classes); `loadQvalRange` + track-class changes use `qvalOptionsFor` (the qval list must be re-rendered whenever the track class changes; keep `/api/qval_range` values cached from the first load). Label rendering: the option label is `label` as given (so `'NA'` shows verbatim, and numeric codes still show `qvalLabel`).
- [ ] **Step 3: PB-11 sequencing.** `reloadOnTrackChange`: `await loadCellTypeClasses(inst)` first, then `Promise.all` of the two subclass loads (they read `cellTypeClass.value`). `reloadOnCellChange`: `await loadTrackClasses(inst)` first, then the two subclass loads. In `setGenome`, `initialLoad` already sequences; additionally, after `loadTrackClasses` resolves, if the retained cell-type-class value is absent from the new list (`setLabeledItems` fell back to the first row), re-run `loadTrackClasses` once so the counts match the resolved cell type class.
- [ ] **Step 4: facet-change detail.** Dispatch `new CustomEvent('facet-change', { detail: { facet } })` from every place that dispatches it (`'track_class' | 'track_subclass' | 'cell_type_class' | 'cell_type_subclass' | 'qval' | 'init'`). Existing listeners ignore `detail` — no behaviour change for them.
- [ ] **Step 5: Live check** on `/peak_browser` (hg38): Bisulfite-Seq → panel 3 shows one row `NA`, "Track type (optional)" shows one row `NA`; Annotation tracks → panel 3 `NA`, "Track type (optional)" lists annotations without `All`, first selected; ATAC-Seq / DNase-seq / Input control → "Track type (optional)" is `NA` only; Histone → 50/100/200/500 and the real antigen list. `/enrichment_analysis` (hg38, Bisulfite-Seq) → panel 3 shows `NA`. Note: the Download/IGV buttons are fixed in Tasks 3-4; here only the lists matter.
- [ ] **Step 6: Verification commands; commit** (`Give FacetFilter production's per-track-class threshold and subclass rules`).

---

### Task 3: Peak Browser page actions (PB-16, PB-23, PB-21) and Bisulfite threshold submission (EA-08)

**Files:**
- Modify: `frontend/pages/peak-browser.ts`, `views/peak_browser.erb`
- Modify: `frontend/pages/enrichment-analysis.ts` (only `qvalCodeToThreshold`)
- Test: `frontend/pages/peak-browser.test.ts`, `frontend/pages/enrichment-analysis.test.ts`

**Interfaces:**
- Consumes: `facet-change` `detail.facet` from Task 2; `qval === 'bs' | 'anno'` from Task 2.
- Produces (exported, pure, tested) in `peak-browser.ts`: `resolveSubclassExclusion(changed: 'track_subclass' | 'cell_type_subclass', track: string, cell: string): { resetFacet: 'track_subclass' | 'cell_type_subclass' | null }` — when both are non-`'-'`, the facet **not** just changed is reset (production `peak_browser.js:318-360`).
- Produces: `qvalCodeToThreshold('bs') === '999'` (production sends `threshold=999` for Bisulfite-Seq, `enrichment_analysis.js:970-999`); `'anno'` still throws (Enrichment Analysis never offers annotation tracks); numeric codes unchanged.

- [ ] **Step 1: Tests**: `resolveSubclassExclusion` (both set + changed track → reset cell; both set + changed cell → reset track; one `'-'` → null); `qvalCodeToThreshold('bs') → '999'`, `('05') → '50'`, `('anno')` throws. Run, see failures.
- [ ] **Step 2: PB-16.** In `peak-browser.ts`'s `facet-change` listener: read `detail.facet`; if it is one of the two subclass facets, call `resolveSubclassExclusion`; when a reset is needed, set that facet's `<select>` value to `'-'`, dispatch a native `change` event on it, and show a dismissible Bootstrap 5 warning (`div.alert.alert-warning.alert-dismissible` with the text `Either an "Antigen" or a "Cell type" is selectable.` and a `button.btn-close`) inside a new `<div class="panel-message" id="subclass-warning"></div>` placed in `views/peak_browser.erb` directly above the two optional panels' row. Only one warning at a time (replace, don't append).
- [ ] **Step 3: PB-23.** In both button handlers: if `res.url === null || !res.url`, do not navigate; set `#action-status` to `No precomputed file exists for this combination. Try a different track type, cell type or threshold.` For IGV, skip the reachability probe in that case.
- [ ] **Step 4: PB-21.** Replace the bare `wiki#igv_doc` link with an `a.info-btn[data-info="igv"]` link ("Error connecting to IGV?") whose popover text is production's verbatim text (`peak_browser.js:426-427`, `viewOnIGV` — keep the three paragraphs, drop the last sentence "Click OK to go to the IGV website, or cancel to back to ChIP-Atlas.") followed by a real link to `https://igv.org/doc/desktop/#DownloadPage/` (opens in a new tab). `info-popover.ts` currently renders `html: false`; add an optional `links?: Record<string, { href: string, label: string }>` argument or render the URL as plain text — choose the simplest that keeps `html: false` for all other popovers (no raw HTML from data).
- [ ] **Step 5: Live check**: Bisulfite-Seq → "Download BED file" now downloads `…/BSF.ALL.bs.AllAg.AllCell.bed` (URL from `POST /api/download_url` with `qval: 'bs'`); Histone / H3K4me3 + Blood / K-562 → picking the second one resets the first to `All` and shows the warning; a combination with no file (e.g. pick an antigen and then a threshold with no data) shows the inline message and stays on the page; "Error connecting to IGV?" opens the help popover.
- [ ] **Step 6: Verification commands; commit** (`Restore Peak Browser's antigen/cell-type exclusion, no-file message and IGV help; send threshold 999 for Bisulfite-Seq`).

---

### Task 4: Ruby services and routes (PB-19 backend, SV-41, SV-34, API-53, JSON-body 400)

**Files:**
- Modify: `lib/services/location_service.rb`, `lib/services/sra_service.rb`, `routes/api.rb`, `lib/middleware/json_body_parser.rb`
- Test: `test/services/location_service_test.rb`, `test/services/sra_service_test.rb` (create if absent), `test/routes/api_test.rb`

**Interfaces:**
- Produces: `LocationService#igv_browsing_url` returns `nil` (never raises) when no bedfile matches; for `Annotation tracks` it looks up filename **and** trackname with `cell_type_class: 'All cell types'` merged in (production `old-app/lib/pj/location.rb:30-36, 58-60`). `POST/GET /api/igv_url` then returns `{ "url": null }` with 200 (same contract as `/api/download_url`).
- Produces: `LocationService#correlation_tsv_url` sanitises both names with `gsub(/[^a-zA-Z0-9_-]/, '_')` (production `old-app/views/experiment.haml:333-338`): `CD4+ T cells` → `CD4__T_cells`, `NIH/3T3` → `NIH_3T3`, `H2A.Z` → `H2A_Z`.
- Produces: `SraService#fetch` never caches `error_metadata` (only real NCBI results are stored; a failure is re-tried on the next view).
- Produces: `/api/colo`, `/api/colo/download`, `/api/target_genes`, `/api/target_genes/download`, `/api/igv_url`, `/api/download_url` respond `400 {"error": ...}` when `genome` is not a key of `ChipAtlas::Experiment.genomes` or is not a String; `/api/target_genes*` respond 400 when `distance` is not one of `ChipAtlas::Analysis::TARGET_GENES_DISTANCES` (find the constant's real name with `grep -rn DISTANCES lib`); the JSON body middleware returns `400 {"error":"JSON body must be an object"}` when the parsed body is not a Hash.

- [ ] **Step 1: Tests first** (rack-test + the fixture DB): igv_url for `Annotation tracks` with `track_subclass: 'CpG Islands'`-style fixture row returns a URL containing `annotations/<genome>/` and `&name=`; with a subclass that has no row → 200 `{"url":null}`; correlation_tsv_url cases above; SraService caching test with a stubbed NCBI failure (follow the stub pattern used in existing tests / `WabiService.poster=` style — add `SraService.fetcher=` if there is no hook yet); `genome=util%2FlineNum.tsv%23` → 400; `distance=7` → 400; JSON body `[1,2]` → 400. Run, see failures.
- [ ] **Step 2: Implement.** Keep changes minimal and local; do not restructure LocationService.
- [ ] **Step 3: `docker restart chip-atlas-local`, wait for `/health`, live check**: `curl -s -X POST localhost:9292/api/igv_url -H 'Content-Type: application/json' -d '{"condition":{"genome":"hg38","track_class":"Annotation tracks","track_subclass":"CpG Islands","cell_type_class":"NA","qval":"anno"}}'` → 200 with a URL (find a real annotation name via `/api/track_subclasses?genome=hg38&track_class=Annotation%20tracks`); the old 500 case → `{"url":null}`; `curl -s 'localhost:9292/api/colo/download?genome=util%2FlineNum.tsv%23&track=x&cell_type=y&format=tsv'` → 400.
- [ ] **Step 4: Verification commands; commit** (`Harden LocationService, SraService and API parameter validation`).

---

### Task 5: Job result pages (DA-26, EA-38, DA-31, EA-41)

**Files:**
- Modify: `frontend/components/result-page-params.ts`, `frontend/components/job-tracker.ts`, `frontend/api/client.ts` (only if a typed 503 body helper is needed), `routes/jobs.rb`
- Test: `frontend/components/result-page-params.test.ts` (create), `frontend/components/job-tracker.test.ts`, `test/routes/jobs_test.rb`

**Interfaces:**
- Produces: `readResultPageParams(search)` requires only `id`. Backend resolution: `backend=` if present; else `api=wabi` → `'wabi'`, any other non-empty `api=` → `'wes'`; else `'wabi'` (production's result URLs were `?id=…&api=wabi&title=…&calcm=…`).
- Produces (exported, pure, tested) in `job-tracker.ts`: `statusFromPollError(err: unknown): string | null` — returns `'backend_unavailable'` when `err` is an `ApiError` with `status === 503` whose JSON body has `status === 'backend_unavailable'` (or `error` mentioning the backend), else null.
- Produces: when a poll yields `backend_unavailable`, the status cell shows `backend_unavailable` (red) and polling **continues** at the normal interval (production keeps polling "server unavailable" so the page recovers when the supercomputer comes back). `'unknown'` is displayed as-is and polling continues.
- Produces: `GET /jobs/:id/result` no longer gates on backend availability — result URLs are deterministic (`ComputeRouter.result_urls`) and production shows them even while the backend is down. `/jobs/:id/status` and `/jobs/:id/log` keep the 503.

- [ ] **Step 1: Tests**: params (`?id=x` → wabi; `?id=x&api=wabi` → wabi; `?id=x&api=https://ea.chip-atlas.org` → wes; `?id=x&backend=wes` → wes; `?title=x` alone → null); `statusFromPollError`; Ruby: `/jobs/abc/result?backend=wabi&type=diff_analysis` returns 200 with the zip URL even when `ServiceMonitor` stub says wabi is down (see how `jobs_test.rb` stubs availability today). Run, see failures.
- [ ] **Step 2: Implement.** In `poll()`'s catch: `const s = statusFromPollError(err); if (s) setStatus(inst, s)`; then reschedule as today.
- [ ] **Step 3: Live check**: `/diff_analysis_result?id=bogus123` (no backend) now shows the table with Status `unknown` and the Download Result URL; `/enrichment_analysis_result?id=bogus&api=wabi` likewise; `/jobs/bogus/result?backend=wabi&type=diff_analysis` → 200.
- [ ] **Step 4: Verification commands; commit** (`Accept production-format result URLs and show backend outages on the result pages`).

---

### Task 6: Re-enable Diff Analysis (DA-01) and restore its panel headings (DA-08, DA-15)

**Files:**
- Modify: `lib/services/compute_router.rb` (`JOB_TYPE_BACKENDS['diff_analysis'] = %w[wabi].freeze`, and rewrite the comment block: WABI serves diff analysis again as of 2026-09-24 per the owner; keep the map as the single switch), `frontend/pages/diff-analysis.ts` (the comment above `UNAVAILABLE_MESSAGE` claiming WABI never serves diff analysis; the help text `Enter a title for the data selected in "2. Enter dataset A".` now matches), `views/diff_analysis.erb` (headings `2. Enter dataset A` / `3. Enter dataset B`, keeping the textareas and "Try with example" links)
- Test: `test/services/compute_router_test.rb`, `test/routes/jobs_test.rb`, `test/routes/pages_test.rb`, `frontend/pages/diff-analysis.test.ts`

- [ ] **Step 1: Tests**: `ComputeRouter.available_backend('diff_analysis')` → `{ backend: 'wabi', available: true }` when the wabi stub is up, `{ backend: nil, available: false }` when down; `POST /jobs/submit` with `type: 'diff_analysis'` reaches the (stubbed) `WabiService.poster` and returns the job id; `GET /diff_analysis` body includes `2. Enter dataset A` and `3. Enter dataset B` and not `Dataset A (Experiment IDs)`. Run, see failures.
- [ ] **Step 2: Implement; also update `/status` expectations** in `test/routes/health_test.rb` if it asserts `diff_analysis: 'unavailable'`.
- [ ] **Step 3: `docker restart chip-atlas-local`; live check**: `curl localhost:9292/jobs/available?type=diff_analysis` → `{"backend":"wabi","available":true}`; `/diff_analysis` shows no unavailable notice and Submit enabled. **Do not submit a real job.**
- [ ] **Step 4: Verification commands; commit** (`Re-enable Diff Analysis on WABI and restore its production panel headings`).

---

### Task 7: Enrichment Analysis form — examples, count-table mode, submit guard, validation (EA-12, EA-13 placement, EA-15, EA-16, EA-24, EA-27)

**Files:**
- Modify: `frontend/pages/enrichment-analysis.ts`, `views/enrichment_analysis.erb`
- Test: `frontend/pages/enrichment-analysis.test.ts`, `test/routes/pages_test.rb`

Production reference: `old-app/public/js/pj/enrichment_analysis.js` lines 338-392 (examples), 452-486 + `views/enrichment_analysis.haml:198-201` (count mode), 613-619 (count payload), 639-689 (validation), 758-803 (submit disable).

**Interfaces:**
- Produces (exported, pure, tested): `exampleFileFor(aType: 'bed' | 'gene' | 'count'): 'bedA.txt' | 'geneA.txt' | 'countA.txt'`; `buildEnrichmentParams` with `aType === 'count'` yields `typeB: 'empty'`, `bedBFile: 'empty'`, no `permTime`, `descriptionA: 'Dataset A from count table header'`, `descriptionB: 'Dataset B not applicable for count table'` (production's internal values); `validateTitleText(label: string, text: string): string | null` returning production's message `Invalid characters are detected in <label>. Acceptable characters are:\n- alphanumerics (abcABC123)\n- space ( )\n- underscore (_)\n- period (.)\n- hyphen (-)` when the text contains anything outside `[A-Za-z0-9 _.-]`, and `validateDistance(text): string | null` (`Invalid characters are detected in Distance from TSS. Acceptable characters are:\n- positive integer (1,2,3,..)` unless `/^\d+$/`).
- Produces: "Try with example" loads `/examples/<genome>/<exampleFileFor(currentMode)>` and does **not** change the radio; a 404 shows `No example data available for this genome and experiment type.` (so TAIR12 works as soon as files are placed).
- Produces: count-table mode UI: panel 5 body shows only `Not required for gene count table analysis` (radios, permutation row, textarea, file picker hidden), panel 6's Dataset A / Dataset B title inputs hidden (labels too); leaving count mode restores everything.
- Produces: the Submit button is `disabled` from click until the request settles (re-enabled on failure; on success the page navigates).
- Produces: validation runs before submit on Analysis title (`Project title`), Dataset A title (`User data title`), Dataset B title (`Compared data title`) and, when the TSS row is visible, both distance fields; the first failure's message goes to `#submit-status` (with `white-space: pre-line`) and submission stops.

- [ ] **Step 1: Tests** for the pure helpers and the count-mode payload (update `enrichment-analysis.test.ts:153-159`, which currently asserts B-derived values for count mode — production sends `empty`). Run, see failures.
- [ ] **Step 2: Implement** (`loadExample`, `syncDatasetBVisibility` count branch, submit handler). Add `id`s to the ERB where needed (e.g. `id="dataB-panel-body"`, `id="count-mode-note"` with `hidden`, `id="dataset-titles"` wrapper) and assert them in `pages_test.rb`.
- [ ] **Step 3: Live check**: hg38 → Gene list → Try with example fills `geneA.txt` (gene symbols) and keeps the Gene list radio; Gene count table → Try with example fills `countA.txt`, panel 5 shows only the note, titles hidden; TAIR12 → message; title with `&` → message, no submission; Submit disables during the request (observe with DevTools throttling or by checking `disabled` right after click via the console).
- [ ] **Step 4: Verification commands; commit** (`Restore Enrichment Analysis's per-mode examples, count-table mode, submit guard and title validation`).

---

### Task 8: Enrichment Analysis — help text, node-status link, taxonomy prefill, availability check (EA-22, EA-26, EA-35, SHELL-39)

**Files:**
- Modify: `frontend/pages/enrichment-analysis.ts`, `views/enrichment_analysis.erb`
- Test: `frontend/pages/enrichment-analysis.test.ts`, `test/routes/pages_test.rb`

**Interfaces:**
- Produces: `NOTE2`'s "Acceptable genome assemblies" block lists exactly the offered assemblies: `hg38 (H. sapiens)`, `mm10 (M. musculus)`, `rn6 (R. norvegicus)`, `dm6 (D. melanogaster)`, `ce11 (C. elegans)`, `sacCer3 (S. cerevisiae)`, `TAIR12 (A. thaliana)`. `NOTE1`'s nomenclature table is left as is (the A. thaliana identifier convention is unconfirmed — add a code comment `// TODO(owner): A. thaliana identifier convention pending backend confirmation (2026-09-24)`).
- Produces (exported, pure, tested): `genomeForTaxonomy(taxid: string | undefined): string | null` — `9606→hg38, 10090→mm10, 10116→rn6, 7227→dm6, 6239→ce11, 4932→sacCer3, 3702→TAIR12`, else null (production's `taxidMap`, `enrichment_analysis.js:31-62, 228-255`, remapped to the offered assemblies). On init, when `prefill.taxonomy` resolves to an offered genome, that tab is selected before the prefill is applied (use the same mechanism `GenomeTabs` uses for `#genome=`; check `genome-tabs.ts` for a `select`/hash API and use it rather than simulating clicks).
- Produces: the setup page checks `checkJobAvailability('enrichment_analysis')` on init exactly like `diff-analysis.ts` does (copy `resolveAvailabilityUiState` + `applyAvailability` — per-page duplication is this codebase's convention); message text: `Enrichment analysis is currently unavailable due to the backend server issue. See the maintenance schedule on the top page.`; Submit disabled while unavailable; failed check fails open (same reasoning as diff-analysis.ts). Add `<div id="unavailable-notice" class="alert alert-warning small mb-2" role="alert" hidden></div>` above the Submit button in the ERB.
- Produces: the setup page's "node status (epyc.q)" link points to `https://sc.ddbj.nig.ac.jp/en/operation/job_queue_status/`.

- [ ] **Step 1: Tests**: `genomeForTaxonomy` cases; `resolveAvailabilityUiState` for EA (message text); `pages_test.rb` asserts the new link href and the notice element; `NOTE2` contains `TAIR12 (A. thaliana)` and not `hg19`. Run, see failures.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Live check**: `curl -s -X POST localhost:9292/enrichment_analysis -d 'taxonomy=10090&genes=Stat3%0ASocs3'` rendered in a browser lands on the mm10 tab with the gene list; the notice is hidden while WABI is up (`/jobs/available?type=enrichment_analysis`).
- [ ] **Step 4: Verification commands; commit** (`Enrichment Analysis: current assemblies in help, working node-status link, taxonomy prefill and availability check`).

---

### Task 9: Shell and small page fixes (SHELL-34, SHELL-20, SHELL-02, SV-27, TG-15)

**Files:**
- Modify: `public/css/style.css`, `views/publications.markdown`, `views/demo.markdown`, `views/updates.markdown`, `views/about.erb`, `frontend/pages/homepage.ts`, `frontend/pages/experiment.ts`, `views/experiment.erb` (if the Analyze button needs an id/hidden hook), `frontend/pages/target-genes.ts`, `frontend/pages/colo.ts`, `views/target_genes.erb`, `views/colo.erb`
- Test: `test/routes/pages_test.rb`, `frontend/pages/homepage.test.ts` (create), `frontend/pages/experiment.test.ts` (create if absent)

- [ ] **SHELL-34:** add `.popover { --bs-popover-max-width: 24rem; } .popover-body { white-space: pre-line; }` to `style.css`. Live check: the EA "Gene list" ⓘ shows its bullet lines on separate lines.
- [ ] **SHELL-20:** kramdown GFM has no bare-URL autolink option (checked: `kramdown-parser-gfm` 1.1.0 only defines `gfm_quirks`). Rewrite the five bare URLs as `<http://…>` autolinks: `views/publications.markdown` lines 4-8 (the "To cite" DOIs and `https://chip-atlas.org`) and `views/demo.markdown` line 21 (`https://chip-atlas.org/llms.txt`). `pages_test.rb`: `/publications` body contains `<a href="http://dx.doi.org/10.1093/nar/gkae358">`. Also delete the stale HTML-comment line (`<!-- - <span style="color:red">**Enrichment analysis will be temporarily unavailable …** -->`) from `views/updates.markdown`.
- [ ] **SHELL-02:** service-status banner on the home page. Add `<div id="service-notice" hidden></div>` in `views/about.erb` immediately above the What's new markdown block. In `homepage.ts`, call `serviceStatus()` (`frontend/api/client.ts`, currently unused) and render, for every entry of `features` whose value is not `'ok'` and not `'ok (backup)'`, one `p.text-danger.fw-bold` line `<Name> is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.` (names: `peak_browser`→Peak Browser, `enrichment_analysis`→Enrichment Analysis, `diff_analysis`→Diff Analysis, `target_genes`→Target Genes, `colo`→Colocalization, `search`→Dataset Search); unhide the div only when at least one line exists; a failed `/status` call renders nothing. Export the pure `unavailableFeatureLines(features: Record<string,string>): string[]` and test it.
- [ ] **SV-27:** in `experiment.ts` do not render the Analyze menu (hide the whole button group) when `data.records[0].track_class === 'Bisulfite-Seq'` (production `experiment.js:126-131`). Export a pure `showAnalyzeMenu(trackClass: string): boolean` and test it. Live check: `/view?id=SRX11233737` has no Analyze button; `/view?id=SRX018625` still has it.
- [ ] **TG-15 (and the same pattern for Colo's two download buttons):** before navigating to `/api/target_genes/download?…` or `/api/colo/download?…`, do `fetch(url, { method: 'HEAD' })`; on `!res.ok` show `No data found for this combination.` in a new `<div id="action-status" class="text-muted small mt-2" aria-live="polite"></div>` under the buttons (add to both ERBs) and stay on the page; on ok, navigate. `routes/api.rb` download endpoints must answer HEAD like GET (Sinatra maps HEAD to GET automatically — verify with `curl -I` and, if the body proxy is expensive for HEAD, short-circuit HEAD after the existence check via `request.head?`).
- [ ] **Verification commands; commit** (`Popover line breaks, clickable citation links, home service banner, Bisulfite Analyze menu, download existence checks`).

---

### Task 10: Documentation and dead data (SHELL-25, SHELL-27, SHELL-31, API-46, API-47, EA-13 cleanup)

**Files:**
- Modify: `views/agents.markdown`, `views/demo.markdown`, `public/llms.txt`, `public/openapi.yaml`
- Delete: `public/examples/hg19`, `public/examples/mm9`, `public/examples/dm3`, `public/examples/ce10` (assemblies no longer offered; `git rm -r`)
- Test: `test/routes/pages_test.rb` (assert `TAIR10` absent from `/agents`, `/demo`, `/llms.txt`, `/openapi.yaml`; assert `cell_type=Blood` example present), plus a Ruby test that parses `public/openapi.yaml` with `YAML.safe_load` and checks every documented path exists as a route (`ChipAtlasApp.routes` keys) — a lightweight drift guard.

Read `docs/review-2026-09-23/findings/api-surface.md` items **API-46** and **API-47**, and `ui-shell.md` items **SHELL-25 / SHELL-27 / SHELL-31** — they list every mismatch with the live evidence.

- [ ] Fix all `TAIR10` → `TAIR12` (6 places); colo examples `cell_type=K-562` → `cell_type=Blood` with a note that `cell_type` is a cell-type *class* from `/api/colo_index`; `/status` description → `services`/`features` string maps (copy the real shape from `curl localhost:9292/status`); every openapi.yaml mismatch listed in API-46 (`/api/genomes` object, `/api/experiment` array, `/status`, `/jobs/submit` `{backend, job_id}`, `/jobs/{id}/status|result|log` shapes, `CUT&Tag/CUT&RUN` removed from enumerations and `Annotation tracks` added where the live `/api/track_classes` has it, diff-analysis submission documented as available). Verify each against the live app with curl before editing.
- [ ] Remove the four dead example directories; `frontend` and Ruby code must not reference them (`grep -rn "hg19\|mm9\|dm3\|ce10" frontend lib routes views public/openapi.yaml public/llms.txt` — leave `/view`'s pipeline text alone if it legitimately mentions old assemblies; report what remains).
- [ ] **Verification commands; commit** (`Bring agent docs and OpenAPI in line with the implementation; drop examples for retired assemblies`).

---

### Task 11: SQLite PRAGMAs per connection with environment overrides (API-54, also LONG-RB-14)

**Files:**
- Modify: `lib/db.rb`, `docs/setup.md` (short "Local development" note), `/Users/inutano/run/chip-atlas-local.sh` (the owner's local launcher, outside the repo)
- Test: `test/db_test.rb` (create)

**Interfaces:**
- Produces: PRAGMAs (`journal_mode=WAL`, `synchronous=NORMAL`, `cache_size=-64000`, `mmap_size`) are applied through Sequel's `after_connect` hook so every pooled/forked connection gets them (today only the first connection does). `SQLITE_MMAP_SIZE` (bytes; default `268435456`) and `SQLITE_LOCKING_MODE` (`NORMAL` default, `EXCLUSIVE` allowed) env vars override; `EXCLUSIVE` avoids the `-shm` mmap that crashes SQLite on Docker Desktop bind mounts (the 2026-09-23 SIGBUS). In-memory test DBs skip PRAGMAs as today.
- Produces: the local launcher passes `-e SQLITE_LOCKING_MODE=EXCLUSIVE -e SQLITE_MMAP_SIZE=0`.

- [ ] **Step 1: Test**: with `DATABASE_URL=sqlite://<tmpfile>` and the env vars set, `DB.synchronize { |c| c.execute('PRAGMA locking_mode') }` (Sequel exposes the raw sqlite3 connection in `synchronize`) reports `exclusive`, and a second connection from the pool reports the same. Run, see failure.
- [ ] **Step 2: Implement** (`Sequel.connect(url, pool_timeout: 300, after_connect: ->(conn) { … })`, guarded by the same `rescue Sequel::DatabaseError`/in-memory check). Update the launcher script and the docs note.
- [ ] **Step 3: Restart the local container with the updated launcher (`bash ~/run/chip-atlas-local.sh`), confirm `/health` and that `docker exec chip-atlas-local ls /app | grep -c 'verify-shm'` shows no `-shm` file after a few requests (`ls -la /Users/inutano/repos/chip-atlas/database.sqlite.verify*`).
- [ ] **Step 4: Verification commands; commit** (`Apply SQLite PRAGMAs on every connection and allow exclusive locking for bind-mounted dev DBs`).
