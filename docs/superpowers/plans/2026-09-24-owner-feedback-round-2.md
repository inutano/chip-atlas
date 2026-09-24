# Owner Feedback Round 2 (2026-09-24) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the eleven application changes (R1–R11) the owner requested after testing the sengu branch on the test EC2 instance, restoring production behaviour where the request says "like the original" and applying the owner's wording elsewhere. R12 (search by GSE/BioProject/BioSample) is an investigation item answered outside this plan.

**Architecture:** Bug fixes first (gene-list submission, IGV genome URL), then the backend search change, then the frontend/CSS work (search rendering, navbar, popover, facet lists, home page), then the Enrichment Analysis form behaviour. Every task is independent of the others except where an *Interfaces* block says otherwise. Production behaviour is the reference; its code is available read-only as a plain copy of git `master` at `SCRATCH/old-app/` (also via `git show master:<path>`) where `SCRATCH = /private/tmp/claude-501/-Users-inutano-repos-chip-atlas/d2f860a9-de11-4510-8b60-649b4cb4f929/scratchpad`. The investigation reports that back each task are under `SCRATCH/investigation/` (read them for evidence and measurements; the task text below is the requirement).

**Tech Stack:** Sinatra 4 + Sequel + SQLite FTS5 (Ruby 4.0.5), ERB (erubi, `escape_html: true`), TypeScript compiled by esbuild into `public/js/*.js`, plain CSS in `public/css/style.css`, minitest + rack-test, `node --test` for frontend unit tests. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-24-owner-feedback-round-2.md` (R1–R12, the owner's words plus the binding interpretation).

## Global Constraints

- **Do not run host-side `sqlite3` or `bundle exec ruby/rake` against `database.sqlite*`** — a Docker container holds an exclusive lock on them and crashes (verified 2026-09-23). Query data through the running app (`http://localhost:9292/api/...`) or inside the container (`docker exec chip-atlas-local bundle exec ruby -e '...'`). Tests use their own fixture DB (see `test/test_helper.rb`).
- **Local instance:** `http://localhost:9292` is Docker container `chip-atlas-local` bind-mounted on this working tree, `RACK_ENV=development`. ERB, CSS and `public/js` changes are live immediately (run `npm run build` after TypeScript changes). Ruby changes need `docker restart chip-atlas-local` (takes 60–90 s; wait for `curl -sf http://localhost:9292/health`).
- **Verification commands (all must pass before every commit):** `bash script/dev/test.sh` (Ruby suite, prebuilt image `chip-atlas-test:local`), `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.json`, `./node_modules/.bin/tsc --noEmit -p frontend/tsconfig.test.json`, `npm run build`, `bash script/dev/test-frontend.sh`, `bash script/dev/ui-checklist.sh` (score must stay 34/34).
- **Zero external dependencies, plain CSS + TypeScript only, no `alert()`/`confirm()` in new code, no `innerHTML` with user data** (build DOM with `createElement`/`textContent`).
- **Templates escape by default;** `<%==` only for trusted server-generated HTML.
- **Keep the existing test conventions:** frontend tests are pure-function tests of exported helpers (no jsdom) in `frontend/**/*.test.ts`; Ruby tests in `test/**/*_test.rb` with `Rack::Test`. Every behaviour change gets a test; DOM wiring gets a manual live check documented in the report (headless driver: `node SCRATCH/tools/cdp.mjs --url URL --wait ms [--js '<expr>']... [--shot out.png] [--mobile]`; each `--js` runs after load, async, 15 s limit; never await a navigating click inside one evaluate).
- **Never submit analysis jobs** (never let `POST /jobs/submit` reach the compute backends from a test or a live check; stub `WabiService.poster` in Ruby tests and intercept `fetch` in browser checks). Never send requests to `dtn1.ddbj.nig.ac.jp` or `ea.chip-atlas.org`.
- **Commit messages:** plain imperative subject, no prefix (repo convention), and end with the two attribution lines:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01LDsEWzb3cA5D6Ndw2YdBFr`.
- Do not modify `docs/review-2026-09-23/`, `docs/superpowers/`, or `.superpowers/` (the controller updates the review documents afterwards).

---

### Task 1: Enrichment Analysis gene-list submissions — always send `permTime`, log rejections (R2)

**Files:**
- Modify: `frontend/pages/enrichment-analysis.ts:716-722` (`buildEnrichmentParams`)
- Modify: `lib/services/wabi_service.rb` (`ENRICHMENT_ANALYSIS_DEFAULT_PARAMS`, `merge_operational_params:151-162`, `submit_job:89-95`, `post:164-171`)
- Modify: `lib/services/compute_router.rb:58-68` (`submit` error hash), `routes/jobs.rb:76-77`
- Test: `frontend/pages/enrichment-analysis.test.ts` (rewrite `:162-168` and `:217-231`, add two tests), `test/services/wabi_service_test.rb:51`, `test/routes/jobs_test.rb` (add a gene-list case next to `:157`), `test/services/compute_router_test.rb` (add one test)

**Interfaces:**
- Produces: `buildEnrichmentParams(condition, form)` always includes `permTime` (`form.permTime || '1'`) for every `aType`/`bType` combination.
- Produces: `WabiService::ENRICHMENT_ANALYSIS_DEFAULT_PARAMS = { 'permTime' => 1 }.freeze`, applied as a *default* (caller's value wins) to every non-diff job in `merge_operational_params`.
- Produces: `ComputeRouter.submit` returns `{ error: :submission_rejected, backend: <backend name> }` on rejection (unchanged success shape).
- Consumes: nothing from other tasks.

Evidence: `SCRATCH/investigation/genelist-502.md` §0–§5. Root cause: the frontend only sends `permTime` when dataset B is "Random permutation"; clicking "Gene list" force-checks dataset B = RefSeq, so gene-list submissions reach WABI without the required `permTime` (`script/enrichment-analysis/enrichment-analysis.cwl:73-74`, `type: int`) and are rejected → `routes/jobs.rb:77` answers 502. Production sends `permTime` unconditionally (`SCRATCH/old-app/public/js/pj/enrichment_analysis.js:605`, `permTime = permTime > 0 ? permTime : 1` at `:586`). The instance's `log/access_log` confirms every one of the owner's submissions today had `typeA=gene` and no `permTime`.

- [ ] **Step 1: Frontend tests first.** In `frontend/pages/enrichment-analysis.test.ts` replace the test at `:162-168` (`permTime is included only when dataset B is random permutation`) with:
  ```ts
  test('buildEnrichmentParams: permTime is always sent, whatever dataset B is', () => {
    // Gating this on bType === 'rnd' made WABI reject every gene-list
    // submission (gene-list mode force-checks dataset B = RefSeq) — 502 from
    // routes/jobs.rb. Production sends it unconditionally.
    for (const bType of ['rnd', 'bed', 'refseq', 'userlist']) {
      const p = buildEnrichmentParams(baseCondition, { ...baseForm, bType, permTime: '10' })
      assert.equal(p.permTime, '10', `permTime missing for dataset B = ${bType}`)
    }
    const blank = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'refseq', permTime: '' })
    assert.equal(blank.permTime, '1') // production's `permTime > 0 ? permTime : 1`
  })
  ```
  Update the count-mode test at `:217-231` so that count mode also always sends it (`assert.equal('permTime' in bed, false)` becomes `assert.equal(bed.permTime, '1')`, and rename/re-comment the test accordingly). Add:
  ```ts
  test('buildEnrichmentParams: gene-list mode sends every field production sends', () => {
    const p = buildEnrichmentParams(baseCondition, { ...baseForm, aType: 'gene', bType: 'refseq' })
    assert.deepEqual(Object.keys(p).sort(), [
      'antigenClass', 'bedAFile', 'bedBFile', 'cellClass', 'descriptionA', 'descriptionB',
      'distanceDown', 'distanceUp', 'genome', 'permTime', 'threshold', 'title', 'typeA', 'typeB',
    ])
  })
  ```
  (If `baseForm`/`baseCondition` in that file produce extra keys such as `wabiID`, adjust the expected list to the real production key set — the point is that the *complete* set is pinned.) Run `bash script/dev/test-frontend.sh`: the three tests fail.
- [ ] **Step 2: Frontend fix.** In `buildEnrichmentParams` replace lines 716–722 (the comment block and `if (form.bType === 'rnd') params.permTime = form.permTime`) with a short comment explaining that production sets `permTime` unconditionally (its `numShuf` radios are hidden, never unchecked, when dataset B is refseq/userlist) and that gating it on `bType === 'rnd'` made WABI reject every gene-list and BED+BED submission, followed by `params.permTime = form.permTime || '1'`. Run the frontend tests: green. `npm run build`.
- [ ] **Step 3: Ruby tests first.** `test/services/wabi_service_test.rb:51`: change `refute captured.key?('permTime')` to `assert_equal 1, captured['permTime'], 'enrichment jobs get permTime=1 when the caller omits it'` and rename the test so it no longer claims permTime is diff-only; add a test that a caller-supplied `'permTime' => '10'` survives the merge unchanged. `test/routes/jobs_test.rb`: next to `:157` add a gene-list end-to-end case that stubs `WabiService.poster`, posts `{ type: 'enrichment_analysis', params: { ...typeA: 'gene', typeB: 'refseq', permTime: '1', ... } }` (the exact key set from Step 1) and asserts the captured hash contains `'permTime'`. `test/services/compute_router_test.rb`: add `test_submit_does_not_fall_back_to_wes_when_wabi_rejects_the_submission` — stub `ServiceMonitor.status` so `:wabi` is up, stub `WabiService.poster` to return `nil`, make a stubbed `SapporoService.submit_job` call `flunk`, and assert the result is `{ error: :submission_rejected, backend: 'wabi' }`. Run `bash script/dev/test.sh`: the new/changed tests fail.
- [ ] **Step 4: Ruby implementation.** `lib/services/wabi_service.rb`: add after line 24
  ```ruby
  # Enrichment analysis: WABI/CWL require permTime on every submission
  # regardless of dataset B's type (enrichment-analysis.cwl declares it
  # `type: int`, not `int?`). The user-facing value wins; this only fills a
  # gap. See DIFF_ANALYSIS_OPERATIONAL_PARAMS for the diff-job equivalent.
  ENRICHMENT_ANALYSIS_DEFAULT_PARAMS = { 'permTime' => 1 }.freeze
  ```
  and in `merge_operational_params`, for `job_type != 'diff_analysis'`, return `ENRICHMENT_ANALYSIS_DEFAULT_PARAMS.merge(merged)` (defaults first so the caller's value wins). Make `post` keep the HTTP status (`@last_status = response.code`, or return `[status, body]` and destructure at both call sites) and make `submit_job` `warn "[wabi] submission rejected: status=#{status.inspect} fields=#{merged.keys.sort.inspect} body=#{body.to_s[0, 500].inspect}"` when no `requestId` can be parsed (field *names* only — never values; `bedAFile` can be megabytes of user data). `lib/services/compute_router.rb`: include `backend: route[:backend]` in the `:submission_rejected` hash. `routes/jobs.rb:76-77`: before the `halt 502`, `log_activity('job_submit_rejected', { type: job_type, backend: result[:backend] })` (mirror the existing success `log_activity` call at `:72`). Run `bash script/dev/test.sh`: green.
- [ ] **Step 5: Live check** (after `npm run build`; no job may leave the browser): on `http://localhost:9292/enrichment_analysis` install a `fetch` interceptor that records the `POST /jobs/submit` body and answers a fake `Response` (status 500) instead of sending, click `#dataA-genes`, click the "Try with example" control, click Submit, and confirm the captured `params` contain `permTime: "1"` together with `typeA: "gene"` and `typeB: "refseq"`. Record the captured key list in the report.
- [ ] **Step 6: Run all verification commands; commit** (`Always send permTime on Enrichment Analysis submissions and log backend rejections`).

---

### Task 2: IGV genome as a JSON URL for every assembly (R1)

**Files:**
- Modify: `lib/services/location_service.rb:22-52` (`igv_browsing_url`, interpolations at `:38` and `:48`)
- Modify: `frontend/components/igv.ts` (new export), `frontend/pages/experiment.ts` (`buildVisualizeMenu:81-109`, export it)
- Modify: `public/openapi.yaml` (~`:1004` and ~`:1073`, the two example `/api/igv_url` response strings)
- Test: `test/services/location_service_test.rb` (`:48-55`, `:149-163`, new TAIR12 test), `test/routes/api_test.rb` (`:138-147`, `:201-215`, new TAIR12 route test), create `frontend/components/igv.test.ts`, extend `frontend/pages/experiment.test.ts`

**Interfaces:**
- Produces: `LocationService#igv_genome_url` (private) → `"#{ARCHIVE_BASE}/genome/#{@genome}/#{@genome}.json"` (`ARCHIVE_BASE` is `https://chip-atlas.dbcls.jp/data`, `location_service.rb:7`).
- Produces: `export function igvGenomeParam(genome: string): string` in `frontend/components/igv.ts` → `` `https://chip-atlas.dbcls.jp/data/genome/${genome}/${genome}.json` ``.
- Produces: `buildVisualizeMenu` exported from `frontend/pages/experiment.ts` (for testability only; behaviour unchanged apart from the genome parameter).

Evidence: `SCRATCH/investigation/igv.md`. Both builders hand IGV's `/load` command a bare genome id (`genome=TAIR12`); IGV has no bundled TAIR12 genome. All seven `https://chip-atlas.dbcls.jp/data/genome/<g>/<g>.json` files exist (HTTP 200) and each JSON's own `id` is its URL. The owner's instruction is that *all* assemblies use the JSON URL, so the helpers take no per-genome branch (hg38 etc. change shape too — say so in the commit body). Interpolate the URL raw, exactly like `file=` already is (none of the seven URLs contains `&`, `=` or a query string).

- [ ] **Step 1: Ruby tests first.** `test/services/location_service_test.rb`: change the regex in `test_igv_browsing_url` (`:48-55`) to assert `genome=https://chip-atlas\.dbcls\.jp/data/genome/hg38/hg38\.json`; add `test_igv_browsing_url_for_tair12_uses_the_genome_json_url` mirroring `test_archive_url_falls_back_to_bed_gz_for_tair12` (`:30-46`) and asserting the returned command contains `genome=https://chip-atlas.dbcls.jp/data/genome/TAIR12/TAIR12.json`; add the same `genome=` assertion to the annotation-tracks test at `:149-163`. `test/routes/api_test.rb`: add the `genome=…json` assertion to `test_post_igv_url` (`:138-147`) and to `:201-215`, and add a test posting a TAIR12 condition to `/api/igv_url` asserting the `.json` shape. Run `bash script/dev/test.sh`: fail.
- [ ] **Step 2: Ruby implementation.** Add the private helper `igv_genome_url` next to `bed_url`/`annotation_url` and use it in both interpolations of `igv_browsing_url`. Run `bash script/dev/test.sh`: green.
- [ ] **Step 3: Frontend tests first.** Create `frontend/components/igv.test.ts` asserting `igvGenomeParam('hg38') === 'https://chip-atlas.dbcls.jp/data/genome/hg38/hg38.json'` and the TAIR12 equivalent. In `frontend/pages/experiment.test.ts` add a test that `buildVisualizeMenu` (exported) for a TAIR12 record produces hrefs whose `genome=` value is `https://chip-atlas.dbcls.jp/data/genome/TAIR12/TAIR12.json` (build the minimal record the function needs; read the function first). Run `bash script/dev/test-frontend.sh`: fail (type errors count as failure — run `tsc --noEmit -p frontend/tsconfig.test.json` too).
- [ ] **Step 4: Frontend implementation.** Add `GENOME_JSON_BASE`/`igvGenomeParam` to `frontend/components/igv.ts`; in `experiment.ts` import it, export `buildVisualizeMenu`, and replace all seven `genome=${g}` occurrences (`:81, :86, :93, :97, :101, :105, :109`) with `genome=${igvGenomeParam(g)}`. `npm run build`; frontend tests green.
- [ ] **Step 5: Docs.** Update both example strings in `public/openapi.yaml` to `http://localhost:60151/load?genome=https://chip-atlas.dbcls.jp/data/genome/hg38/hg38.json&file=...` (keep the rest of each example). `public/llms.txt`, `views/agents.markdown`, `views/demo.markdown` need no change (their `genome=` is the request parameter).
- [ ] **Step 6: Live check.** `curl -s -X POST http://localhost:9292/api/igv_url -H 'Content-Type: application/json' -d '<a TAIR12 condition; copy the shape from test/routes/api_test.rb>'` returns a URL containing `genome=https://chip-atlas.dbcls.jp/data/genome/TAIR12/TAIR12.json`; open a TAIR12 experiment page (find an SRX via `curl -s 'http://localhost:9292/api/search?q=TAIR12&limit=1'`, then `/view?id=<SRX>`) in the headless driver and read the Visualize menu hrefs. Record both in the report. (A real IGV desktop is not available; note that in the report.)
- [ ] **Step 7: Run all verification commands; commit** (`Hand IGV the genome JSON URL for every assembly`).

---

### Task 3: Dataset Search prefix matching (R10)

**Files:**
- Modify: `lib/models/experiment_search.rb` (`:97` call site, `:150-159` `fts5_sanitize` → public `match_expression`, `MIN_PREFIX_LENGTH`)
- Modify: `public/openapi.yaml:645-659` (one sentence on `q`: terms are prefix-matched)
- Test: `test/models/experiment_search_test.rb`, `test/routes/api_test.rb:103-113`

**Interfaces:**
- Produces: `ExperimentSearch.match_expression(query) → String` (public, pure) and `ExperimentSearch::MIN_PREFIX_LENGTH = 2`.
- Produces (contract for Task 4): tokenisation = whitespace-split, `"quoted phrases"` kept whole, the characters `" ' ( ) * ^ { } :` stripped from every term, empty terms dropped.

Evidence: `SCRATCH/investigation/search.md` §1.4, §3. The FTS table is FTS5 (`db/migrations/001_create_schema.rb:79-91`, unicode61, no `prefix=` index); `"term"*` works on any FTS5 table and costs the same as an exact match for the same hit count (measured at 432k rows), so no schema change and no metadata reload.

- [ ] **Step 1: Tests first.** In `test/models/experiment_search_test.rb` add `test_match_expression_*` cases: `'K56'` → `'"K56"*'`; `'K562 chip'` → `'"K562"* "chip"*'`; `'a'` → `'"a"'` (below `MIN_PREFIX_LENGTH`); `'"chip antibody" K56'` → `'"chip antibody"* "K56"*'`; `'K56*'` → `'"K56"*'` (user's `*` absorbed); `'a AND b'` → `'"a" "AND"* "b"'` (operators neutralised); `'***'`, `'""'`, `'   '` → `''`. Add a search-level test that `search('K56', ...)` finds the fixture rows that `search('K562', ...)` finds (check the fixture cell types in `test/test_helper.rb`/fixtures). Re-check `test_search_by_keyword` (`:23-27`) and `test_search_with_genome_filter` (`:29-33`) against the wider semantics and adjust the expected counts only if the fixture really gains prefix hits. In `test/routes/api_test.rb` extend `test_search` (`:103-113`) with a prefix case (`q=K-56` hits the seeded `K-562` row). Run `bash script/dev/test.sh`: fail.
- [ ] **Step 2: Implement.**
  ```ruby
  MIN_PREFIX_LENGTH = 2

  # Turn a user query into an FTS5 MATCH expression.
  #   bare term of >= MIN_PREFIX_LENGTH chars -> "term"*   (prefix match)
  #   shorter term                            -> "term"    (exact; a 1-char
  #                                              prefix scans the whole index)
  #   "quoted phrase"                         -> "quoted phrase"*  (phrase prefix)
  # Every term stays inside double quotes, which is what keeps FTS5 operator
  # keywords (AND/OR/NOT/NEAR) and metacharacters from being parsed as syntax.
  def self.match_expression(query)
    terms = []
    query.to_s.strip.scan(/"([^"]*)"|(\S+)/) do |phrase, bare|
      cleaned = (phrase || bare).to_s.gsub(/["'()*^{}:]/, '').strip
      next if cleaned.empty?
      terms << (cleaned.length >= MIN_PREFIX_LENGTH ? %("#{cleaned}"*) : %("#{cleaned}"))
    end
    terms.join(' ')
  end
  ```
  (Adapt `self.`/module style to how the file defines its other methods.) Call it from `search` at `:97` instead of `fts5_sanitize`; the existing empty-expression guard at `:98` stays; remove `fts5_sanitize` and its `private_class_method` line. Run `bash script/dev/test.sh`: green.
- [ ] **Step 3: Docs.** In `public/openapi.yaml:645-659` add to the `q` parameter description: "Each term matches as a prefix (`K56` finds `K562`); quote a phrase to match it whole." Run the OpenAPI drift test if one exists (`test/routes/openapi_test.rb`).
- [ ] **Step 4: Live check** (`docker restart chip-atlas-local`, wait for `/health`): `curl -s 'http://localhost:9292/api/search?q=K56&limit=1'` reports a total in the thousands (today 4) and `q=K562` at least what it returned before (6,978). Record both totals.
- [ ] **Step 5: Run all verification commands; commit** (`Match Dataset Search terms as prefixes`).

---

### Task 4: Dataset Search — hit window and click-to-expand (R9)

**Files:**
- Modify: `frontend/pages/search.ts` (`:18` constant, `renderAttributesCell:80-101`, `renderRow:103-139`, `renderResults:141-172`)
- Modify: `public/css/style.css` (after `:251`)
- Test: `frontend/pages/search.test.ts`

**Interfaces:**
- Consumes: Task 3's tokenisation contract (mirror it in `searchTerms`).
- Produces (all exported, pure, tested):
  ```ts
  export const ATTRIBUTES_WINDOW_LENGTH = 100   // replaces ATTRIBUTES_TRUNCATE_LENGTH
  export function searchTerms(query: string): string[]          // whitespace-split, "quoted phrases" whole, FTS metacharacters " ' ( ) * ^ { } : dropped, empty terms dropped
  export function firstHitIndex(formatted: string, terms: string[]): number   // earliest case-insensitive occurrence of any term, or -1
  export function attributesWindow(formatted: string, terms: string[], length = ATTRIBUTES_WINDOW_LENGTH): string
  export function highlightSegments(text: string, terms: string[]): Array<{ text: string; hit: boolean }>
  ```
  `attributesWindow` rules: (1) `formatted.length <= length` → `formatted` unchanged; (2) no hit → `formatted.slice(0, length) + '…'` (today's behaviour); (3) otherwise `start = clamp(hit - Math.floor((length - hitLength) / 2), 0, formatted.length - length)`, window = `formatted.slice(start, start + length)`, prepend `'…'` iff `start > 0`, append `'…'` iff `start + length < formatted.length`. `highlightSegments` returns alternating segments covering the whole text; hits are case-insensitive matches of any term, longest term first at a given position, never overlapping.

Evidence: `SCRATCH/investigation/search.md` §2, §4.2 (screenshots `search-attrs-collapsed.png` / `-expanded.png`). Today `renderAttributesCell` puts `formatted.slice(0, 100) + '…'` in the `<summary>` and the whole text in a sibling `div`, so opening shows the first 100 characters twice and a hit past offset 100 never appears. The window is computed client-side: the client already has the full `attributes` string (also used by `toTsv`) and the query; the API and OpenAPI stay unchanged (server-side FTS5 `snippet()` was tested and conflicts with the `COUNT(*) OVER()` in the same query).

- [ ] **Step 1: Tests first** in `frontend/pages/search.test.ts`: `searchTerms('K562 "chip antibody" (x)')` → `['K562', 'chip antibody', 'x']`; `searchTerms('')` → `[]`; `firstHitIndex('Cell line: k562', ['K562'])` → `11`, no hit → `-1`, multi-term earliest wins; `attributesWindow`: short string returned unchanged (no ellipsis); hit inside the first 100 chars of a long string → window starts at 0 with trailing `…` only; hit at offset 300 of a 500-char string → leading and trailing `…`, hit inside the returned text; hit near the end → window clamped to the tail, no trailing `…`; no hit → first 100 chars + `…`; `highlightSegments('a K562 b', ['k562'])` → `[{text:'a ',hit:false},{text:'K562',hit:true},{text:' b',hit:false}]`, no terms → one plain segment. Run `bash script/dev/test-frontend.sh`: fail.
- [ ] **Step 2: Implement the helpers** in `search.ts` (rename `ATTRIBUTES_TRUNCATE_LENGTH` → `ATTRIBUTES_WINDOW_LENGTH`; keep `formatAttributes` and `toTsv` untouched). Frontend tests green.
- [ ] **Step 3: Render.** `renderResults` computes `const terms = searchTerms(state.query)` once per page and passes it to `renderRow(row, terms)` → `renderAttributesCell(attributes, terms)`. New cell DOM (built with `createElement`/`textContent`, hits wrapped in `<mark>` via `highlightSegments`):
  ```html
  <td class="search-attrs-cell">
    <details>
      <summary>
        <span class="search-attrs-window">…vendor/catalog=SantaCruz, <mark>catalog</mark># sc-232X</span>
        <span class="search-attrs-less">Show less</span>
      </summary>
      <div class="search-attrs-full">…full formatted text, hits marked…</div>
    </details>
  </td>
  ```
  When `formatted.length <= ATTRIBUTES_WINDOW_LENGTH` render the plain (hit-marked) text without `<details>`, as today. CSS to add after `public/css/style.css:251`:
  ```css
  #search-tbody td.search-attrs-cell .search-attrs-less { display: none; }
  #search-tbody td.search-attrs-cell details[open] .search-attrs-window { display: none; }
  #search-tbody td.search-attrs-cell details[open] .search-attrs-less { display: inline; }
  #search-tbody td.search-attrs-cell mark { padding: 0; background: #fff3cd; }
  ```
  `npm run build`.
- [ ] **Step 4: Live check** on `http://localhost:9292/search` with `q=catalog` (7,494 hits; on page 1 most rows have the term past offset 100): collapsed rows show a window containing the highlighted term; clicking a summary replaces the window with "Show less" and shows the full text once (no duplicated prefix); clicking again collapses. Screenshot both states (headless driver) and record in the report. Also check a query with no attribute hit (`q=CTCF`) still shows the head window.
- [ ] **Step 5: Run all verification commands; commit** (`Show Dataset Search attribute hits in context with a single click-to-expand`).

---

### Task 5: Remove the navbar ID form and make Search read as a link (R11)

**Files:**
- Modify: `views/_navbar.erb:62-72`
- Modify: `public/css/style.css:86-88`, `:139-141`, `:320-323` (delete) and add `.nav-search-link` rules
- Test: `test/routes/pages_test.rb` (add one test; `:112-125` and `:137-141` must keep passing)

**Interfaces:** none.

Evidence: `SCRATCH/investigation/search.md` §5. The form is `views/_navbar.erb:62-68` (`#jumpToExperiment` + Go, inline `onsubmit` → `window.open('/view?id=…')`); no frontend JS, no parity marker (`script/dev/parity-markers.txt` has none for it, score stays 34/34), no doc mentions it. Below 1375 px the Search item currently abbreviates to `🔍 ?`. The controller's ruling: keep the other items' abbreviations unchanged; the Search item always shows the word "Search"; the link gets an outlined pill (calm, no solid white button).

- [ ] **Step 1: Test first.** In `test/routes/pages_test.rb` add `test_navbar_has_no_experiment_id_form`: GET `/`, `refute_includes last_response.body, 'jumpToExperiment'`, `refute_includes last_response.body, 'navbar-id-form'`, and `assert_includes last_response.body, 'nav-search-link'`. Run `bash script/dev/test.sh`: fail.
- [ ] **Step 2: Markup.** Delete `views/_navbar.erb:62-68` (the whole `<form class="navbar-id-form">`); keep the `.navbar-right-stack` wrapper and the `<a href="/search">` inside it; add class `nav-search-link` to that anchor; change its `<span class="abbrev-text">?</span>` to `<span class="abbrev-text">Search</span>`. Nothing else in the navbar changes.
- [ ] **Step 3: CSS.** Delete the `#jumpToExperiment` rules at `:86-88` and `:139-141` (keep the surrounding `@media (max-width: 1375px)` block for the other items) and `.navbar-id-form` at `:320-323`. Add:
  ```css
  .navbar-right-stack .nav-search-link {
    border: 1px solid rgba(255, 255, 255, .5);
    border-radius: .25rem;
    padding: 4px 12px;
  }
  .navbar-right-stack .nav-search-link:hover,
  .navbar-right-stack .nav-search-link:focus { background: rgba(255, 255, 255, .15); }
  ```
  Keep the existing `.navbar-right-stack .nav-link:hover,` selector that `test/routes/pages_test.rb:140` asserts.
- [ ] **Step 4: Live check.** Screenshots of `http://localhost:9292/` at 1440 px, 1200 px (`--width 1200` if the driver supports it, else note) and `--mobile`: no ID input, no Go button, the Search pill visible in the bar (or in the collapsed menu on mobile), no horizontal overflow. `bash script/dev/ui-checklist.sh` still 34/34.
- [ ] **Step 5: Run all verification commands; commit** (`Remove the navbar experiment-ID form and style Search as a link`).

---

### Task 6: Info popovers close on an outside click (R6)

**Files:**
- Modify: `frontend/components/info-popover.ts:62-101`
- Test: create `frontend/components/info-popover.test.ts`

**Interfaces:**
- Produces (exported, pure, tested): `export function isOutsideClick(target: Node | null, trigger: Node, tip: Node | null): boolean` — `false` when `target` is `null`, or `trigger.contains(target)`, or `tip !== null && tip.contains(target)`; `true` otherwise. Uses only `Node.contains`, so tests pass duck-typed objects (`{ contains: (n) => n === child }`).

Evidence: `SCRATCH/investigation/ui-polish.md` §R6. The component wires Bootstrap 5 `Popover` with `trigger: 'focus click'` and registers no document-level listener; Bootstrap binds focus/blur to the trigger only, and Bootstrap's Escape handling belongs to Dropdown/Modal/Offcanvas, not Popover. Live test: the popover stays open after a click on `document.body`. Production's ⓘ was a blocking `alert()`, so there is no old behaviour to restore — the requirement is the owner's wording.

- [ ] **Step 1: Test first.** `frontend/components/info-popover.test.ts`: `isOutsideClick(null, trigger, tip)` → false; target inside trigger → false; target inside tip → false; target elsewhere → true; `tip === null` and target elsewhere → true. Run `bash script/dev/test-frontend.sh`: fail.
- [ ] **Step 2: Implement.** Export `isOutsideClick`. In the popover wiring keep the `Popover` instance in scope; on `shown.bs.popover` add a `document` `pointerdown` listener (capture phase) that resolves the current tip via `document.getElementById(trigger.getAttribute('aria-describedby'))` (Bootstrap rebuilds the tip on every show) and calls `popover.hide()` when `isOutsideClick(event.target as Node, trigger, tip)`; on `hidden.bs.popover` remove the listener. Each trigger owns its own listener; opening a second popover must not leave the first one's listener dangling (remove in `hidden.bs.popover` unconditionally). Do not change the existing trigger/toggle behaviour.
- [ ] **Step 3: Live check** (after `npm run build`) on `http://localhost:9292/enrichment_analysis` with the headless driver: click an `.info-btn` → a `.popover` exists; dispatch `new PointerEvent('pointerdown', { bubbles: true })` on `document.body` → no `.popover` remains; click the button again → popover shows; dispatch `pointerdown` inside the popover element → it stays open; click the trigger itself → toggles as before. Repeat once on `/peak_browser`. Record results.
- [ ] **Step 4: Run all verification commands; commit** (`Close info popovers on a click outside them`).

---

### Task 7: Facet list typography and home-page card alignment (R7, R8)

**Files:**
- Modify: `public/css/style.css` (`select.list-box` at `:450-462`, `select.list-box option`, `.jumbotron` at `:391`, the `@media (max-width: 767px)` block that stacks the cards)
- Test: none (CSS only; live measurements are the acceptance test)

**Interfaces:** none.

Evidence: `SCRATCH/investigation/ui-polish.md` §R7–§R8 with measurements. R7: `select.list-box` sets no `font-size`, so rows inherit Bootstrap 5's 16px where production's Bootstrap 3 `<select class="form-control" size="8">` had 14px with `line-height: 1.42857143`; the new rule also zeroes the select's own padding (production keeps `6px 12px`), so the net inset is smaller although the option padding (`2px 6px`) is numerically larger than production's UA default (`0 2px 1px`). Measured: new rows 22px at 16px vs production 17px at 14px; the surrounding `.card`/`.card-body` spacing already matches. R8: the top page (`views/about.erb`) renders `.col-icon`/`.col-labels` as direct children of `.jumbotron`, which is `display: flex; align-items: center`; production used floated Bootstrap 3 grid columns, which top-align. Measured: new icon/label share one vertical centre; production's icon top and label top are identical.

- [ ] **Step 1: Facet lists.** In `select.list-box` set `font-size: 14px; line-height: 1.42857143; padding: 6px 12px;` (replacing `padding: 0`) and set `select.list-box option { padding: 0 2px 1px; }` (replacing `2px 6px`). Keep every other declaration. `grep -n "list-box" views/*.erb frontend/components/*.ts` to confirm no inline style or `size` logic depends on the old row height (`qvalListBoxSize` in `frontend/pages/peak-browser.ts` sets the row *count*, which is unaffected).
- [ ] **Step 2: Home cards.** Change `.jumbotron { align-items: center }` to `align-items: flex-start`, and inside the existing `@media (max-width: 767px)` block that sets `flex-direction: column` add `.jumbotron { align-items: center; }` so the stacked mobile layout keeps the icon centred (in a column flexbox the cross axis is horizontal). `grep -n "jumbotron" views/*.erb` to confirm only the six home cards use the class; if another page does, keep its look unchanged (scope the rule) and say so in the report.
- [ ] **Step 3: Live measurements** with the headless driver on `http://localhost:9292/peak_browser` vs `https://chip-atlas.org/peak_browser`: first row of "1. Track type class" — `getComputedStyle` font-size 14px on both, row height (option `getBoundingClientRect().height`) within 1px of production, select padding 6px 12px. On `http://localhost:9292/` vs `https://chip-atlas.org/`: in the first two cards, `.col-icon` top equals `.col-labels` top (±1px) as on production. Screenshots of both pages at 1440 px and `--mobile` (mobile: icon still centred above the label). Record numbers in the report.
- [ ] **Step 4: Run all verification commands; commit** (`Match production's facet list typography and top-align the home-page cards`).

---

### Task 8: Enrichment Analysis dataset B — hide choices per mode, dataset B example, clear on radio change (R3, R4, R5)

**Files:**
- Modify: `views/enrichment_analysis.erb:79-91` (panel 5 rows, labels, a dataset-B file row with its example link)
- Modify: `frontend/pages/enrichment-analysis.ts` (`syncDatasetBVisibility:320-382`, new pure helpers next to `countModeVisibility:307-318` and `exampleFileFor:774-778`, `loadExample:780-805`, the radio bindings at `:970-972` and the example binding at `:984-987`)
- Modify: `docs/ui-parity-audit-2026-09-14.md:174` (append one sentence: the disabled "gene-list mode only" radios were reversed on 2026-09-24 at the owner's request — panel 5 now hides them like production)
- Test: `frontend/pages/enrichment-analysis.test.ts` (new cases next to `countModeVisibility`'s at `:290-317` and `exampleFileFor`'s at `:99-125`), `test/routes/pages_test.rb:245-307`

**Interfaces:**
- Consumes: Task 1's `buildEnrichmentParams` (permTime always sent) — do not touch that function.
- Produces (exported, pure, tested):
  ```ts
  export function datasetBRadioVisibility(aType: 'bed' | 'gene' | 'count'): { rndHidden: boolean; bedHidden: boolean; refseqHidden: boolean; userlistHidden: boolean }
  // bed   → { false, false, true, true }
  // gene  → { true, true, false, false }
  // count → { true, true, true, true }   (the whole #dataB-panel-body is hidden by countModeVisibility anyway)
  export function exampleFileForB(bType: 'bed' | 'userlist'): 'bedB.txt' | 'geneB.txt'
  export function clearedTextareaFor(changedGroup: 'dataA-type' | 'dataB-type'): 'dataA-text' | 'dataB-text'
  ```

Evidence: `SCRATCH/investigation/ea-forms.md` §1 (production's behaviour, live-verified), §2, §4. Production (`SCRATCH/old-app/public/js/pj/enrichment_analysis.js:76-110, 357-392, 394-486, 523-575`; `master:views/enrichment_analysis.haml:151-197`): dataset A = BED shows dataset B's "Random permutation" and "Genomic regions (BED)" rows and hides "Refseq coding genes" and "Gene list" (default Random); dataset A = Gene list shows Refseq and Gene list and hides Random and BED (default Refseq); count hides all four. Hiding is real `display: none` on the row wrapper, never `disabled`. Two "Try with example" links exist: dataset A's (always visible, loads `bedA/geneA/countA.txt` for the *currently checked* A radio without changing it — already implemented as `#try-example`) and dataset B's, which sits in the same wrapper as dataset B's textarea/file input, so it is visible exactly when dataset B = BED or Gene list, and loads `bedB.txt` (BED) or `geneB.txt` (Gene list) into dataset B's textarea. A user click that changes dataset A's radio clears only dataset A's textarea; a click that changes dataset B's radio clears only dataset B's textarea; switching A force-reassigns B's radio programmatically and does **not** clear B's text (verified on production both ways). Selecting Gene list makes no network request. The new app instead toggles `disabled` on `dataB-refseq`/`dataB-userlist` (labels say "(gene-list mode only)"), never hides `dataB-rnd`/`dataB-bed`, has no dataset-B example link (the files `public/examples/<genome>/bedB.txt`, `geneB.txt` already exist for every genome), and never clears a textarea. The controller's rulings: hidden rows use the `hidden` attribute on the `.form-check` wrapper (`radio.closest('.form-check')`); the two labels revert to production's wording in this app's style — `Refseq coding genes (excluding dataset A)` and `Gene list (symbols or IDs)`; the `applyDatasetBGateTransition` default/stash logic (tested at `enrichment-analysis.test.ts:319-417`) stays as is.

- [ ] **Step 1: Frontend tests first** in `frontend/pages/enrichment-analysis.test.ts`: `datasetBRadioVisibility` for `bed`, `gene`, `count` exactly as in the Interfaces block; `exampleFileForB('bed') === 'bedB.txt'`, `exampleFileForB('userlist') === 'geneB.txt'`; `clearedTextareaFor('dataA-type') === 'dataA-text'`, `clearedTextareaFor('dataB-type') === 'dataB-text'` (with a comment that a dataset-A change never clears dataset B — production's `eraseTextarea` is group-scoped). Run `bash script/dev/test-frontend.sh`: fail.
- [ ] **Step 2: Markup.** In `views/enrichment_analysis.erb`: remove `disabled` from `#dataB-refseq` and `#dataB-userlist`, put `hidden` on their `.form-check` wrappers (the server-rendered default is dataset A = BED), change their labels to `Refseq coding genes (excluding dataset A)` and `Gene list (symbols or IDs)`; wrap `#dataB-file` in a file row mirroring dataset A's block at `:66-70` exactly (same classes; ids `dataB-file-row`, `dataB-file`, and `<a class="linkExample" href="#" id="try-example-b">Try with example</a>`), initially `hidden`. Keep `#dataB-text`, `#dataB-note`, `#permutation-row`, `#count-mode-note` and every `info-btn` as they are. If `script/dev/parity-markers.txt` has a needle for a changed label, update the needle to the new label (the marker's intent is unchanged) and say so in the report.
- [ ] **Step 3: Ruby test first.** In `test/routes/pages_test.rb` (near `:250-257`): assert the page body contains `id="try-example-b"`, contains `Refseq coding genes (excluding dataset A)`, and does not contain `gene-list mode only`. Run `bash script/dev/test.sh`: fail; then it passes with Step 2's markup (no Ruby code change).
- [ ] **Step 4: Behaviour.** In `enrichment-analysis.ts`: add the three helpers; in `syncDatasetBVisibility` replace the two `disabled` assignments with `hidden` on the four rows' `.form-check` wrappers from `datasetBRadioVisibility(aType)`, and make the `needsInput` block toggle `dataB-file-row` (not `dataB-file`) together with `dataB-text`; add `loadExampleB()` mirroring `loadExample()` (reads `getCheckedValue('dataB-type')`, fetches `/examples/<genome>/<exampleFileForB(bType)>` into `#dataB-text`, dispatches the same `input` event as `:800`, same error handling) and bind it to `#try-example-b` at init; add per-radio `change` listeners (in the same loop as `:970-972`) that clear `document.getElementById(clearedTextareaFor(radio.name))` (`value = ''` + the same `input` event) *before* the existing sync runs — only the group whose radio the user changed. Programmatic `checked = true` assignments (the gate transition) do not fire `change`, so the asymmetry holds without extra state. `npm run build`; frontend tests green.
- [ ] **Step 5: Live check** on `http://localhost:9292/enrichment_analysis` with the headless driver (visibility = `offsetParent !== null`): default → rnd/bed rows visible, refseq/userlist rows not visible, no "(gene-list mode only)" text; click `#dataA-genes` → rnd/bed rows not visible, refseq (checked) and userlist visible, `#permutation-row` hidden; click `#dataA-bed` → back; click `#dataA-count` → `#dataB-panel-body` hidden. Click `#dataA-bed`, then `#dataB-bed` → `#dataB-text`, `#dataB-file-row` and `#try-example-b` visible; click `#try-example-b` → `#dataB-text` holds the first lines of `/examples/hg38/bedB.txt`; click `#dataA-genes` then `#dataB-userlist` → example link visible; click it → `geneB.txt` content. Clearing: set `#dataA-text` to `chr1\t100\t200`, set `#dataB-text` to `x` via a real `#dataB-bed` click first, then click `#dataA-genes` → `#dataA-text` is `''` and `#dataB-text` is still `x`; click `#dataB-userlist` → `#dataB-text` is `''`. Confirm no `fetch` fires on a radio click (install the logger used in Task 1's live check). Record every result.
- [ ] **Step 6: Docs line** in `docs/ui-parity-audit-2026-09-14.md:174` as described in Files.
- [ ] **Step 7: Run all verification commands; commit** (`Restore production's dataset B behaviour on Enrichment Analysis`).

---
