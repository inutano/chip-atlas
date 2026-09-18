# SDD ledger — plan: docs/superpowers/plans/2026-09-18-post-parity-fixes.md

Spec: none separate. The plan IS the spec; its authorities are Tazro's 17
decisions (artifact 5f380562, collection `decisions`) and chip-atlas_update_260915.pdf.
Branch: sengu @ 0c66277 (not a main/master branch; user directed execution here).
Scope: all tasks EXCEPT B4 (user: "B4以外を進めてください"; B4 blocked on Q2, out with collaborator).
Baseline: 104 runs, 545 assertions, 0 failures. tsc clean. checklist 34/34.

## Preflight scan

### Cross-task pairs sharing a file or interface

| Tasks | produces → consumes | finding |
|---|---|---|
| A1 → A2 | config/genomes.yml carries TAIR12 key → A2 relies on the rename | consistent; A2 text says "done in A1" |
| A1 → A3 | genome list from config → A3 filters both stores by it | consistent |
| A1 → B1 | GENOMES accessor → Analysis loader filters by it | consistent |
| A1 ↔ D2 | both edit lib/models/experiment.rb (GENOMES vs EXPERIMENT_TYPES) | different constants, serial dispatch — no conflict |
| A2 ↔ B2/B5 | all edit lib/services/location_service.rb | different methods (bed_url vs target/colo urls), serial — no conflict |
| B1 → B2 | `track` (bare antigen) + `distance` ('1'\|'5'\|'10') → B2 builds `<TF>.<kb>.tsv` | consistent; interface recorded below |
| B2 → B3 | paginated API (headers, rows, sort/order/offset/limit) → B3 renders | consistent |
| B4 → B5 | colo index → makes the result page reachable | **B4 EXCLUDED — see Ruling 1** |
| A2(step 4) → B4 | "Colo genome strip derives from which genomes have a colo index" | **B4 EXCLUDED — see Ruling 2** |
| C1 ↔ C2 | C1 renames user-facing fields; C2 adds operational fields | disjoint field sets; C1 must not add C2's four |
| C1 ↔ C3 | both near routes/jobs.rb | C1 is frontend+openapi, C3 is router/health — no overlap |
| C1 ↔ C5 ↔ D2 | three tasks edit frontend/pages/enrichment-analysis.ts | serial; C1 first, then C5+D2 batched onto its result |
| D1 ↔ D3 | both edit views/search.erb + frontend/pages/search.ts | batched into one dispatch |
| A3 → D1 | /api/search already returns title/attributes | consistent, verified live |

### Per-task self-consistency

| Task | own text agrees with itself? |
|---|---|
| A1 | yes — config format given, every consumer enumerated |
| A2 | step 4 depends on an excluded task — Ruling 2 |
| A3 | yes |
| B1 | yes — interim source named, indirection justified |
| B2 | yes — TSV shape verified live against the data server |
| B3 | yes — depends only on B2's API |
| B5 | yes — TSV shape verified live; reachability is Ruling 1 |
| C1 | yes — rename table complete; the two encodings explicitly separated |
| C2 | marked "needs sign-off" — Ruling 3 |
| C3 | "driven by config" does not say which config — Ruling 4 |
| C4, C5, D1, D2, D3 | yes |

## Rulings (preflight)

Ruling 1: B5 ships its API and parser and is verified through /api/colo with
production naming (genome=hg38&track=STAT3&cell_type=Blood — the TSV is live,
263 KB, verified). The result view is wired but cannot be driven from the picker
until B4 lands. — Why: the parser and matrix renderer are the bulk of the work
and are independently testable; blocking them on a collaborator's answer wastes
the run. — Cost if wrong: the UI wiring may need adjusting when B4 defines the
real index shape; the parser will not.

Ruling 2: A2 step 4 is narrowed to "TAIR12 must not appear on /colo", hardcoded
against a list of genomes known to have colo data, with a TODO pointing at B4 to
replace it with a derived check. — Why: the derived check needs B4's index.
— Cost if wrong: one small follow-up edit in B4.

Ruling 3: C2 proceeds as written (WabiService supplies address, format, result,
sbatchOptions). — Why: raised with Tazro twice in writing, including the caveat
that it is technically a thin translation layer against D7; he then said proceed.
— Cost if wrong: four fields move from the server to the frontend payload.

Ruling 4: C3's per-job-type availability is a constant map inside ComputeRouter
(job_type => [backends]), not a new config file. — Why: config/genomes.yml exists
because the genome set changes with the data; backend routing changes with code.
— Cost if wrong: a small extraction into config later.

## Interfaces fixed at preflight

- B1 produces / B2 consumes: `track` = bare antigen name (`STAT3`, no suffix);
  `distance` = one of '1' | '5' | '10'; result file = `<genome>/target/<track>.<distance>.tsv`.
- B2 produces / B3 consumes: `{ columns: [...], rows: [[...]], total: n, offset: n, limit: n }`.
- C1 produces / C2 consumes: frontend sends only user-facing WABI fields;
  WabiService merges address, format, result, sbatchOptions.

## Progress

Dispatch order (12 dispatches for 15 tasks; C2+C3, C5+D2, D1+D3 batched):
A1 → A2 → A3 → B1 → B2 → B3 → B5 → C1 → {C2,C3} → C4 → {C5,D2} → {D1,D3}

Task A1: dispatched (sonnet, agent ae530c0f07e240e49), BASE 0c66277
Task A1: implementer DONE (commit ea5839b; 105 runs/550 assertions/0 failures; tsc 0; checklist 34/34)
  Implementer found 2 extra GENOMES consumers (bedfile.rb, bedsize.rb) and a hardcoded
  TAIR10 list in clean_old_genomes.rake; converted all three.
Task A1: review dispatched (sonnet, agent ac45d545d52ab345b), range 0c66277..ea5839b
Task A1: complete (commits 0c66277..ea5839b, review clean — spec ✅, quality approved, 0 Critical/Important)

Ruling 5: A2 verifies TAIR12 loading against a TAIR12-only slice of experimentList.tab
in a temp DB, not by rebuilding the 650 MB production DB. The one full rebuild happens
in A3, which owns the loader change. — Why: two full rebuilds cost many minutes each and
A2 would disturb database.sqlite.latest while the dev server is serving from it.
— Cost if wrong: A3 discovers a TAIR12 loading problem A2 could have caught earlier.

Task A2: dispatched, BASE ea5839b
Task A2: implementer DONE (commit f0dfe57; 111 runs/558 assertions/0 failures, stable over 5 seeds; tsc 0; checklist 34/34)
  Concerns raised: bed_url does a live HEAD probe on cache miss (deliberate, per brief);
  GENOMES_WITH_COLO is a hardcoded allowlist with TODO->B4 (per Ruling 2);
  analyses.cell_list is "-" for every genome and hg38 absent from the table (data-quality,
  belongs to B4 — matches the parity report's Colo finding).
Task A2: review dispatched (sonnet, agent a2cbb38d0a07a5cc0), range ea5839b..f0dfe57
  Reviewer pointed at probe robustness: timeout, 5xx/unreachable behaviour, negative-result
  caching, unbounded cache growth, and whether the test stub can pass vacuously.
Task A2: review — spec ✅, quality CHANGES NEEDED.
  Critical: test/routes/api_test.rb:115,126,147 now reach chip-atlas.dbcls.jp for real.
    bed_url -> BedExtensionResolver.resolve, and ApiTest never stubs the prober; the
    container runs without --network none. Tests pass only because assertions check a
    domain substring, so the breach is silent. Pre-existing tests the diff forgot to update.
  Important: a timed-out/failed probe is cached exactly like a confirmed one, pinning a
    genome to a guessed extension for 1h — during the very migration window this task is for.
  Minor (deferred): unbounded @cache growth; no synchronization under threaded Puma;
    worst case ~30s (2x15s) on a synchronous request path.
Ruling 6: fix round 1 carries the Critical, the Important, AND the cache bound + timeout
  reduction, though the latter two were filed Minor. — Why: they live in the same ~40 lines
  the Important fix rewrites; splitting them costs a second round on the same file.
  — Cost if wrong: a slightly larger fix diff to review.
Task A2: fix round 1/5 dispatched (resumed original implementer), FIX_BASE f0dfe57
Task A2: fix round 1 implemented (commit 3320b36; 116 runs/568 assertions/0 failures,
  5 seeds; full suite also passed under `docker run --network none`, directly proving
  network-freedom; tsc 0; checklist 34/34)
Task A2: scoped re-review dispatched (sonnet, agent ad7586216a2bc1fd9), range f0dfe57..3320b36
  Also asked: should script/dev/test.sh pin --network none permanently? (it does not today)
Task A2: fix round 1/5 (4 addressed, 0 open; commits f0dfe57..3320b36)
  Confirmed: CONFIRMED_TTL 3600s vs ASSUMED_TTL 5s; FIFO cache bound 2000; worst case
  30s -> 8s; LiveProbeNotStubbed raises under RACK_ENV=test, and test_helper.rb:3 sets
  RACK_ENV unconditionally at load so the guard cannot be skipped by omission.
Task A2: complete (commits ea5839b..3320b36, review clean)
Task A2: minor (deferred): BedExtensionResolver @cache/@prober not synchronized under threaded Puma.

Ruling 7: pin `--network none` in script/dev/test.sh. — Why: the resolver's guard only
  covers BedExtensionResolver; the flag is an independent layer catching any future leak
  (DataProxy, new services), and the full suite already passes under it, so it is proven
  safe today. Folded into the A3 dispatch rather than a separate round-trip.
  — Cost if wrong: a test that legitimately needs the network fails and the flag comes out.

Task A3: dispatched, BASE 3320b36
Task A3: implementer DONE with a correctness concern (commit 9e38e79; 121 runs/588
  assertions/0 failures; --network none pinned; checklist 34/34). Concern: sra_id now
  blank for every FTS row; geo_id reconstructed by GSM-prefix extraction from titles (~86%).

Controller verification of that concern (evidence the reviewer could not easily gather):
  experimentList.tab  15 cols, HAS QC stats (col8 "25716567,92.4,46.0,18768"), NO sra_id.
  ExperimentList_adv.json  10 fields, HAS sra_id (idx1) and a real geo_id (idx2), NO QC stats.
  Upstream serves both: data/metadata/ExperimentList.json and .../ExperimentList_adv.json -> 206.
  `experiments` has no sra_id column at all; only experiments_fts ever carried it.

Ruling 8: the brief's "load both stores from experimentList.tab in one pass" is a PLAN
  DEFECT I authored — that file cannot feed both stores without losing sra_id and the real
  geo_id. Corrected requirement: unify the ROW MEMBERSHIP, not the file. One reconciled key
  set + genome filter drives both loaders; experiments keeps the tab's QC stats joined with
  sra_id/geo_id from the JSON; FTS takes the JSON fields over exactly that key set minus
  annotation tracks. Drift stays impossible, nothing is lost. — Why: the plan optimised for
  "one file" when the actual goal is "one row set"; no single upstream file has all columns.
  — Cost if wrong: the loader reads two files instead of one, which it already did.
Task A3: fix round 1/5 dispatched (resumed original implementer), FIX_BASE 9e38e79
Task A3: fix round 1 implemented (commit 4a35f1d; 124 runs/603 assertions/0 failures;
  checklist 34/34; live DB and dev container untouched throughout).
  Drift reconciled in both directions: 544 tab-only / 219 JSON-only.
  Implementer concerns: (a) migration 002 adds sra_id/geo_id to `experiments` per my literal
  instruction, but nothing reads them there — asked the reviewer to judge, I took no view;
  (b) self-caught a raw NUL byte written into experiment.rb during editing, replaced the
  construct; controller confirmed zero NUL bytes remain repo-wide.
Task A3: review dispatched (sonnet, agent ac5dbf985296c57cb), range 3320b36..4a35f1d
  Reviewer also asked to check comment accuracy at metadata.rake:39 and :77 (one may be
  stale from the rejected first pass) and that the NUL replacement is correct, not just clean.
Task A3: review — spec ✅, quality APPROVED, 0 Critical / 0 Important. Two Minors:
  (a) test/test_helper.rb:107-109 comment now stale — it describes load_from_json as the
      cache's invalidation hook, but this task deleted that method.
  (b) experiments.sra_id/geo_id are inert schema: reviewer verified record_by_experiment_id
      excludes them, routes never reference them, and gsm_to_srx reads experiments_fts.geo_id.
      Verdict "dead weight": doubles two string fields across ~454k rows that already live
      populated in experiments_fts, and fixes no part of the orphan bug.
Ruling 9: drop the two columns and migration 002 rather than defer, and fix the stale
  comment in the same round — even though both are filed Minor. — Why: I caused (b) with an
  over-literal instruction, and schema is the one kind of debt that gets harder to unwind
  after a rebuild ships; code Minors can wait, an unused column on 454k rows should not.
  — Cost if wrong: a later task that wants sra_id on `experiments` re-adds a nullable column,
  which is exactly as cheap then as now.
Task A3: fix round 2/5 dispatched (resumed original implementer), FIX_BASE 4a35f1d
Task A3: fix round 2 implemented (commit 894b003; 124 runs/603 assertions/0 failures;
  db/migrations/ back to 001 only, confirmed by controller; checklist 34/34).
  Third rebuild identical: 0 orphans, 453,932 non-empty sra_id/geo_id, 453,705 real sra_id,
  389,223 real geo_id. Implementer also found and removed two more NUL bytes it had written
  into its own report markdown (same root cause as the experiment.rb one).
Task A3: scoped re-review dispatched (haiku, agent afd6351f748d59427), range 4a35f1d..894b003
  Key risk flagged to reviewer: the fix must keep the JSON join (it feeds experiments_fts);
  only the extra write onto `experiments` was to go.
Task A3: fix round 2/5 (2 addressed, 0 open; commits 4a35f1d..894b003)
Task A3: complete (commits 3320b36..894b003, review clean)

Ruling 10: B1's interim human index is a VENDORED SNAPSHOT of target_genes_analysis.json
  committed to the repo, not a fetch from chip-atlas.org at runtime or at build time.
  — Why: D5 makes the regenerated analysisList.tab the long-term source; until it covers
  human, the new app must not acquire a dependency on the old site in either direction.
  A checked-in 49 KB file with a TODO is deletable in one line when upstream lands, and
  public/analysisList.tab sets the precedent for vendoring data here.
  — Cost if wrong: the snapshot goes stale between now and the upstream fix; it covers an
  antigen list that changes slowly, and the file is dated in-repo.

Task B1: dispatched, BASE 894b003
Task B1: implementer DONE (commit 422e0a8; 127 runs/0 failures; tsc 0; checklist 34/34;
  live-verified /api/target_genes_index returns bare names, hg38=1766 incl. STAT3, and
  /api/target_genes/download?...&format=tsv -> 200).
  Found the dotted-antigen trap for real: `wdr-5.1` is a genuine antigen name; controller
  independently confirmed it is the only one today, 6 occurrences. Naive split would give `wdr-5`.
  Implementer concern (correctly out of B1's scope, owned by B2): GET /api/target_genes with
  no `format` still requests <track>.<distance>.json, which does not exist on the archive.
Task B1: review dispatched (sonnet, agent a8ddf539dcc4d282e), range 894b003..422e0a8
  Reviewer focus: dotted-name parsing, legacy-genome leakage from the vendored snapshot,
  fallback precedence, and whether the split broke any other reader of `track`.
Task B1: review — spec ✅, quality approved with 1 Important:
  split_track_and_distance rpartitions on the last dot UNCONDITIONALLY, with no check that
  the trailing component is actually 1/5/10. Safe today only because all 8,345 real rows
  happen to end that way (verified by awk, not by code). A future row like `some.antigen.name`
  would be silently mangled to track="some.antigen"/distance="name".
  Minor (deferred): stopgap comment blocks in analysis.rb are long — deliberate, deletion-marked.
Ruling 11: the Important enters the fix loop now despite the reviewer calling it a follow-up.
  — Why: this run exists because an upstream feed changed shape without warning; a parser
  that trusts that feed's shape unconditionally is the same bug one layer down. The guard is
  a few lines and the drift-counting pattern is already established in A3.
  — Cost if wrong: a slightly stricter parser rejects a row shape that later turns out valid,
  and the count in the load report makes that visible immediately.
Task B1: fix round 1/5 dispatched (resumed original implementer), FIX_BASE 422e0a8
Task B1: fix round 1 implemented (commit 3398ca9; 129 runs/0 failures; tsc 0; checklist 34/34).
  Live run reports {total: 4505, unrecognized_shape: 0}. Controller check: 4505 is exactly the
  supported-genome subset of analysisList.tab (2598 mm10 + 201 rn6 + 788 dm6 + 486 ce11 +
  201 sacCer3 + 231 TAIR12), so the genome filter is provably correct, not coincidentally close.
Task B1: scoped re-review dispatched (haiku, agent ac7a02822b6dcd2d3), range 422e0a8..3398ca9
Task B1: fix round 1/5 (1 addressed, 0 open; commits 422e0a8..3398ca9)
  Guard verified non-vacuous: removing it flips test_split..._refuses_to_guess... from
  ['Foo.Bar', nil] to ['Foo','Bar']. wdr-5.1 case still passes unchanged.
Task B1: complete (commits 894b003..3398ca9, review clean)
Task B2: dispatched, BASE 3398ca9
Task B2: implementer DONE (commit 996027d; 155 runs/680 assertions/0 failures under
  --network none; tsc 0; checklist 34/34; live-verified against real mm10/hg38 data).
  Out-of-brief fix, flagged for review: routes/pages.rb's global Sinatra not_found handler
  was replacing EVERY /api/* JSON 404 body with the HTML not-found page. Pre-existing —
  reproduces on the untouched /api/colo — and it blocked verifying B2's own 404 requirement.
  Left dead: LocationService#target_genes_data_url (and its twin #colo_data_url), both still
  building the never-existed .json path.
Task B2: review dispatched (sonnet, agent a2bed616af29197cd), range 3398ca9..996027d
  Reviewer focus: whether the cache bound is real (entry count is not a bound when one entry
  is ~1.8M cells), limit cap, numeric-vs-lexicographic sort, the not_found scope call, and
  whether the two dead .json builders are a trap.
Task B2: review — spec ✅, quality approved with 2 Important:
  (a) the not_found fix changes every /api/* 404, but only /api/target_genes' 404 is tested.
      /api/colo has zero tests in api_test.rb; the generic /api/whatever -> JSON and the
      non-API -> HTML claims rest on manual curl only.
  (b) /api/colo/download and /api/target_genes/download halt 404 with bare text 'File not
      found' and no content_type, so they now silently become generic {"error":"Not found"}.
      A net improvement over the old mislabeled HTML, but untested and unmentioned.
  Minor (deferred): report arithmetic inconsistent (129+28 != 155); module comment in
  target_genes_tsv.rb states the average-column precedence backwards vs the code.
  Reviewer verified the not_found fix against Sinatra's real invoke semantics (a bare `next`
  returns nil, which leaves body/status untouched) — diagnosis and scoping both correct.
IMPORTANT FOR B5: colo_data_url is NOT dead code. /api/colo still calls it (routes/api.rb:159)
  and it carries the identical never-existed-.json defect, so /api/colo remains live-broken.
  B5 owns removing it. Recorded here so it is not lost.
Task B2: fix round 1/5 dispatched (resumed original implementer), FIX_BASE 996027d
Task B2: fix round 1 implemented (commit 17bff03; 159 runs/697 assertions/0 failures under
  --network none; tsc 0; checklist 34/34). not_found now covered in pages_test.rb plus two
  route-independent regressions in api_test.rb, each confirmed by the implementer to fail on
  a manual revert of routes/pages.rb. Both download routes now emit {"error":"File not found"}.
Task B2: scoped re-review dispatched (haiku, agent a753ef7a477fe374c), range 996027d..17bff03
  Asked the reviewer to judge the "fails on revert" claim from the test code itself rather
  than taking it on trust.
Task B2: fix round 1/5 (4 addressed, 0 open; commits 996027d..17bff03)
  Revert-proof confirmed: report carries the actual failing run (4 tests, JSON::ParserError
  "unexpected character: '<!DOCTYPE'") when routes/pages.rb is reverted. Arithmetic now
  reconciles: 129 + 26 = 155, 155 + 4 = 159.
Task B2: complete (commits 3398ca9..17bff03, review clean)
Task B3: dispatched, BASE 17bff03
Task B3: implementer DONE_WITH_CONCERNS (commit d8748db; 161 runs/0 failures; tsc clean;
  production esbuild build clean; checklist 34/34).
  Concerns: (a) removed a client-side gene-name filter that only filtered the loaded page of
  100 out of 13,459 rows — genuinely misleading; no server-side search param exists. Product
  question, recorded for Tazro, not a blocker. (b) PAGE_SIZE=100 is a judgment call.
  (c) NO BROWSER VERIFICATION — the chrome extension was unreachable in their environment;
  they curled every request the client issues instead.
Controller action on (c): a UI task with no visual check is the gap that matters most — in
  the earlier parity work every significant find came from looking, not from tests. Starting
  a verification container on database.sqlite.rebuild (port 9393, DB with the new analyses
  data) to render the page myself before sending it to review. database.sqlite.latest was NOT
  swapped (size unchanged at 650416128; mtime moved only by WAL checkpoint on shutdown).
Controller visual verification of B3 (rendered at 1440px against database.sqlite.rebuild,
  port 9393, real mm10/Stat3 data): PASSES. Header + "Stat3 on mm10 - TSS +/- 1 kb"; distance
  switcher with +/-1 active; Download TSV; colour legend 0/1/250/500/750/1000+ matching
  production's MACS2/STRING scale; "Show experiment columns (131)" collapsed by default (the
  column-axis decision, and a good one); Gene/Average/STRING table with correct colour coding;
  Stat3 itself top at 1021.21 in red, so the default Average sort is right; real STRING values
  present (Socs3 718 yellow, Mcl1 475 green, Icam1 401).

OPERATIONAL (not a code defect, must not be lost): database.sqlite.rebuild was generated
  during A3, BEFORE B1 added migration 002_add_distance_to_analyses. Its `analyses` table has
  no `distance` column, so /api/target_genes_index raises on it. Whoever swaps a rebuilt DB
  into place must regenerate it AFTER all migrations, not reuse the A3-era artifact.
Task B3: review dispatched, range 17bff03..d8748db
Task B3: review — spec ✅, quality CHANGES NEEDED.
  Important: sortable column headers are keyboard-inaccessible. makeSortableHeader
    (target-genes-result.ts:133-150) and the inline experiment-header build (:178-208) attach
    only a click listener to a plain <th> — no tabindex, no role, no keydown. A <th> is not
    natively focusable, so sorting is mouse-only. The disclosure (<details>), pagination
    (<button>) and distance switcher (<a>) are all native and fine; this is a gap in the
    task's own new control.
  Minor: dead GENE_COLUMN const; sort-toggle logic duplicated between the generic helper and
    the inline experiment-column path; no retry affordance on a failed fetch (previous table
    is discarded); a sort persisted across a distance switch could name a column absent from
    the new TSV -> 400 UnknownSortColumn, which the client reports as "may not have
    precomputed data", mischaracterising the failure.
  Reviewer confirmed clean: no innerHTML/template-HTML anywhere (all textContent/property
    assignment), the single <%== is a static icon name, and 400px overflow is contained by
    #result-table-wrap's overflow-x:auto with collapsed columns using display:none.
Ruling 12: fix round 1 carries the Important plus the sort-persistence guard and the two
  code Minors. — Why: all four live in the same two functions the keyboard fix must edit;
  and the sort-persistence case turns a recoverable 400 into a misleading "no data" message,
  which is a correctness-of-reporting bug, not cosmetics. Retry affordance stays deferred.
  — Cost if wrong: a marginally larger fix diff on one file.
Task B3: fix round 1/5 dispatched (resumed original implementer), FIX_BASE d8748db
Task B3: fix round 1 implemented (commit 0813426; 161 runs; tsc clean; production build clean;
  new script/dev/test-frontend.sh 11/11 via node:test + esbuild, no new dependency; 34/34).
  Headers are now real <button>s (native Enter/Space, aria-sort + visually-hidden state),
  sort guarded across distance switch, dead const removed, toggle logic deduped.

Controller correction: I initially read a clipped 420px screenshot as horizontal overflow.
  That was a Chromium artifact — it clamps windows to 500px minimum. Re-measured with
  Emulation.setDeviceMetricsOverride at a true 390px: collapsed state is clean
  (docScrollWidth 390 == viewport, zero offenders). The reviewer's code-level read was right.

BUT, measured with the 131 experiment columns EXPANDED at 390px:
  viewport 390, docScrollWidth 24575, pageScrollsX TRUE, headerCount 134.
  #result-table-wrap does have overflow-x:auto and does scroll internally, yet #result-table
  still reaches right:24583 — the table escapes its container, drags <body> to 24575px, and
  the 100%-width navbar follows it out to 1560. This violates the global constraint that the
  page body must never scroll horizontally. The code review cleared 400px from the COLLAPSED
  state, where the columns are display:none; expanding is what breaks it.
Ruling 13: this goes to fix round 2 rather than being deferred, and I will run ONE scoped
  re-review over d8748db..HEAD covering both rounds instead of one per round. — Why: the
  defect is a named global constraint, found after round 1 was already in flight; re-reviewing
  round 1 alone would verify a state I already know is incomplete. — Cost if wrong: the
  re-review reads a slightly larger diff.
Task B3: fix round 2/5 dispatched (resumed original implementer), FIX_BASE 0813426
Task B3: fix round 2 implemented (commit c59eb5a). Root cause: documentElement.scrollWidth
  (not body.scrollWidth, which stayed bounded) tracked the wrapper's internal content width
  regardless of overflow-x:auto, and under mobile viewport emulation that fed Chromium's
  viewport-fitting and widened the layout viewport, dragging the fixed navbar along.
  `contain: layout paint` on #result-table-wrap fixes it — one CSS property; a table-layout:fixed
  attempt was tried and reverted. Implementer sanity-checked its own regression script by
  disabling the fix and confirming it reproduces my exact numbers (24575/1560), then restoring.
  Checked in script/dev/measure-target-genes-overflow.mjs and script/dev/test-frontend.sh.
Controller independent re-measurement after the fix: viewport 390, docScrollWidth 390,
  pageScrollsX False, headerCount 134, wrapper still scrolling internally. Defect gone.
Task B3: combined scoped re-review dispatched (sonnet, agent a625857b977984d65),
  range d8748db..c59eb5a, covering both rounds per Ruling 13. Also asked it to judge the two
  unrequested checked-in dev scripts for justification and rot risk.
Task B3: fix rounds 1-2 (all findings addressed, 0 open; commits d8748db..c59eb5a)
  Reviewer confirmed: real <button> headers with aria-sort + visually-hidden state, padding
  moved from <th> to .tg-sort-btn so the hit area is unchanged, /view link now a sibling of
  the button (avoids invalid link-in-button), reverted table-layout attempt cleanly gone,
  and nothing inside #result-table-wrap relies on escaping it (no sticky/fixed/absolute
  descendants; the focus ring uses outline-offset:-2px so containment does not clip it).
Task B3: complete (commits 17bff03..c59eb5a, review clean)

Reviewer's tooling verdict (mixed), carried forward:
  script/dev/test-frontend.sh — justified, low rot risk. Generic runner over frontend/**/*.test.ts
    via esbuild + node:test, no new dependency. BUT not wired into CI or test.sh.
  script/dev/measure-target-genes-overflow.mjs — borderline. Hardcodes mm10/Stat3/1, needs a
    live real-data server on a fixed port, and its pass condition (docScrollWidth <= clientWidth)
    does NOT assert the table is wide enough to exercise the regression. If that antigen's data
    ever shrinks below the column count needed to overflow 390px, it passes silently.
Ruling 14: fold two small items into B5's dispatch rather than spending a round here —
  wire test-frontend.sh into CI, and make the overflow script assert its own precondition so
  it cannot pass without actually exercising the overflow. — Why: a check that can pass while
  testing nothing is the exact class I treated as Critical in A2; leaving it as a deferred
  minor would be inconsistent. Folding into the next dispatch worked well for Ruling 7.
  — Cost if wrong: B5's diff carries two unrelated files, clearly labelled as such.

Task B5: dispatched, BASE c59eb5a
Task B5: implementer DONE (commits 65b383c colo matrix, 01b90dc CI frontend tests,
  709a242 overflow-check precondition; 176 runs/768 assertions/0 failures; tsc 0;
  production build ok; test-frontend 27/27; checklist 34/34).
  Concerns: Average column left uncoloured (production's gradient not reverse-engineerable
  from one dataset); no row pagination (all 3,862 rows rendered); the `10`-as-self-comparison
  sentinel is inferred from live data, not a documented contract.
Controller verification (I first saw 0 rows — that was a STALE CONTAINER: Sinatra does not
  hot-reload Ruby, and /api/colo was still the pre-B5 code. After `docker restart`, 200.):
  render at 1440 = 3,862 rows, 21 headers, no page-level X scroll, 89,079 DOM nodes.
  Performance measured, "no pagination" is FINE at this size: forced layout 1ms, JS heap 2MB,
  DOMContentLoaded 33ms, rows present within the load window; same at 390px.
  Visual: both legends present (H-H..Same concordance, and N.D./0/250/500/750/1000+ STRING),
  reference-experiment columns collapsed (16), Experiment linked to /view, STRING colour-coded.
  Data matches production exactly - top row SRX347427 / SU-DHL-4 / STAT3 / 3.87 is production's
  own first row.
Task B5: review dispatched, range c59eb5a..709a242
Task B5: review — spec ✅, quality APPROVED.
  Important: the `10` self-comparison sentinel is a pure value->label lookup with no
    cross-check against row/column experiment identity. Reviewer's assessment: well-reasoned
    (the H/M/L product formula {1,2,3,4,6,9} caps a real score at 9, so 10 is mathematically
    unreachable except as the sentinel), confirmed against production's own pre-rendered HTML,
    disclosed in three places, and unknown values already fall back to a visible gray "?".
    Residual risk is only a FUTURE encoding change reusing 10, which would render confidently
    wrong with no error.
  Minor (deferred): formatScore/scoreToRgb/rgbToHex/readableTextColor/computeNextSort/
    computeAriaSort are byte-identical across target-genes-result.ts and colo-result.ts.
    Justified by esbuild per-page entry points and documented in both headers; the reviewer's
    trigger for extracting a shared module is a THIRD matrix page.
  Verified clean: dead colo_data_url AND target_genes_data_url both gone, zero references
    repo-wide; no innerHTML anywhere (createElement/textContent only); the overflow CSS block
    is genuinely SHARED between the two pages, not copy-pasted.
Ruling 15: fix the sentinel by structural verification rather than accepting the inference.
  The row carries its Experiment ID (col 1) and each column header is `<SRX>|<CellType>` — so
  "is this cell the query experiment compared with itself?" is directly checkable. Label
  "Same" only when identity matches; a 10 without matching identity takes the gray "?" path.
  — Why: this converts an inferred, undocumented data contract into one the code verifies at
  runtime, and removes the only failure mode the reviewer called confidently-wrong-and-silent.
  Cheap, and the data needed is already in hand. — Cost if wrong: if identity strings ever
  differ in formatting, some genuinely-same cells show "?" instead of "Same" — a visible,
  safe degradation rather than a false label.
Task B5: fix round 1/5 dispatched (resumed original implementer), FIX_BASE 709a242
Task B5: fix round 1 implemented (commit 019ca43; test-frontend 32/32, +5 covering isSelf
  true/false and 4 isSelfComparison cases; test.sh unchanged 176/768/0; tsc 0; build ok;
  checklist 34/34). Identity compared with exact string equality — verified live for
  SRX347427 and SRX347429, no fuzzy matching needed or added; self-column still renders
  "Same"/black under the structural check.
Task B5: scoped re-review dispatched (haiku, agent af014616933dc374b), range 709a242..019ca43
Task B5: fix round 1/5 (1 addressed, 0 open; commits 709a242..019ca43)
  Verified: exact === on the SRX accession (no normalisation), the `10: Same` entry is gone
  from CONCORDANCE_COLORS entirely so there is no raw-value short-circuit left, and the test
  asserts notEqual 'Same' for the non-matching case.
Task B5: complete (commits c59eb5a..019ca43, review clean)
Task C1: dispatched, BASE 019ca43
Task C1: implementer DONE_WITH_CONCERNS (commit cb2494f; 176 runs/768 assertions/0 failures;
  frontend 41/41 (+9); tsc 0; build ok; checklist 34/34).
  Concern: diff-analysis.ts still sends `analysis`/`dataA_ids`/`dataB_ids`. The implementer
  found that production's diff payload uses a different shape from the enrichment rename
  table it was given, and correctly declined to guess.
Ruling 16: that is a defect in MY brief, not the implementation. C1's file list named
  frontend/pages/diff-analysis.ts, but the rename table I supplied was enrichment-shaped, so
  it did not cover diff's mapping. D7 ("frontend emits WABI's own names") is an app-wide
  decision; leaving one of the two job-submitting pages on names WABI does not know means it
  breaks again the moment that backend returns. Dispatching a fix round with the actual
  production diff payload, which I captured during the parity investigation:
    antigenClass=diffbind|dmr, typeA=srx, bedAFile=<newline-joined SRX ids>, descriptionA,
    typeB=srx, bedBFile=<newline-joined>, descriptionB, title, genome, cellClass=empty,
    permTime=1, threshold=50 (diffbind) / 999 (dmr), sbatchOptions, address, format, result.
  — Cost if wrong: diff payload field names change once more when its backend is restored.
Task C1: fix round 1/5 dispatched (resumed original implementer), FIX_BASE cb2494f
Task C1: fix round 1 implemented (commit 4f1c253; Ruby 176/768/0 unchanged; frontend 45/45
  (32 baseline + 9 enrichment + 4 diff); tsc 0; build ok; checklist 34/34). Diff payload now
  antigenClass/bedAFile/bedBFile/descriptionA/descriptionB with newline-joined ids; the nine
  operational fields are pinned ABSENT by test so C2 cannot double-add them.
Controller verification of the encoding hazard: /api/qval_range still returns
  ["05","10","20","50"] (unchanged, correct — those name files), and the frontend converts at
  the WABI boundary via qvalCodeToThreshold = n*10 (05->50, 10->100, 20->200, 50->500).
  That is the genuine relationship (code = threshold/10), not a curve fitted to four points.
  NOTE this is a deliberate deviation from my brief, which said to change the option values:
  the implementer kept codes as values because the same facet feeds Peak Browser's file
  lookups, and converts only where WABI's encoding is needed. Handed to the reviewer to judge
  rather than blessing it myself.
Task C1: review dispatched (sonnet, agent a2b7f2e35b6f01014), range 019ca43..4f1c253
Task C1: review — spec ❌ (one gap), quality CHANGES NEEDED.
  Gap/Important: public/openapi.yaml:319-352 DiffAnalysisParams still documents the PRE-rename
    fields (analysis, dataA_ids/dataB_ids as arrays). The rename landed in the second commit,
    which touched only diff-analysis.ts and its test. openapi.yaml was named in scope. The
    suite validates openapi only for YAML syntax, not content, so this is real silent drift.
  Important: qvalCodeToThreshold's NaN fallback returns the unparseable code unchanged and
    sends it to WABI as `threshold`. It mirrors facet-filter.ts's qvalLabel, but that
    precedent is display-only (a mislabeled dropdown); this one is submission-time to a live
    compute service. On a task whose entire purpose is defusing quiet-wrong-result hazards,
    it should throw.
  Minor (deferred): the report's openapi section predates the second commit and never flagged
    the staleness, so a reader trusting the report would miss it.
  Reviewer's verdict on the deviation: SOUND — and notes that following my brief literally
    (changing the option values) "would have broken Peak Browser's file lookups, trading one
    hazard for another", since peak-browser.ts:58 and facet-filter.ts:334 need the raw code
    to build allPeaks_light.<genome>.<code>.bed.gz. That is the THIRD defect in my own plan
    text this run; the implementer was right to deviate and right to say so.
Task C1: fix round 2/5 dispatched (resumed original implementer), FIX_BASE 4f1c253
Task C1: fix round 2 implemented (commit 8fb80ba; Ruby 176/768/0; frontend 46/46; tsc 0;
  build ok; checklist 34/34; openapi re-validated). DiffAnalysisParams now matches the shipped
  payload, EnrichmentAnalysisParams cross-checked with no drift, qvalCodeToThreshold throws on
  an unparseable code and the throw surfaces through the existing submit-failure path rather
  than as an unhandled rejection.
Task C1: scoped re-review dispatched (haiku, agent a14d3014b8dd9af3e), range 4f1c253..8fb80ba
  Told the reviewer to compare the schemas field-by-field against the two build*Params
  functions rather than trusting the report, and to confirm the throw is HANDLED by reading
  the call site.
Task C1: fix round 2/5 (3 addressed, 0 open; commits 4f1c253..8fb80ba)
  Reviewer compared both schemas field-by-field against the build*Params functions (13/13
  enrichment fields match, conditionals correctly marked) and confirmed at the CALL SITE that
  buildEnrichmentParams now sits inside the try block, so the throw reaches the existing catch
  and shows a user-facing submit-failure message rather than an unhandled rejection.
  Filename codes confirmed undisturbed: facet-filter.ts unchanged, Peak Browser still gets the
  raw code.
Task C1: complete (commits 019ca43..8fb80ba, review clean)
Tasks C2+C3: dispatched as one batch, BASE 8fb80ba
Tasks C2+C3: implementer DONE (commits 70f5562 C2, 9eef92f C3; 208 runs (+32); frontend
  46/46; tsc 0; checklist 34/34; no real job submitted — all submission paths stubbed via a
  new WabiService.poster=).
  Concerns: (1) diff's server-side merge is unreachable because JOB_TYPE_BACKENDS
  ['diff_analysis'] == [] by design — tested by temporarily patching the constant. Intentional.
  (2) No frontend wiring for the honest "unavailable" state. (3) Chose 502 for
  "backend rejected the submission" vs 503 for "no backend available"; not specified by me.
Ruling 17: concern (2) is another internal inconsistency in MY brief — C3's file list named
  only compute_router.rb / routes/jobs.rb / routes/health.rb, while its Verify section asked
  for UI behaviour. The implementer was right to flag rather than silently widen scope. I am
  relocating the UI wiring to C4, which already owns frontend/pages/diff-analysis.ts, instead
  of a fix round here. — Cost if wrong: the unavailable state lands one task later than planned.
Ruling 18: accept 502-for-rejected / 503-for-no-backend. — Why: 503 is correct for "no
  backend available"; for a submission WABI answered with something we could not parse a
  request id out of, 502 (upstream returned an invalid response) is the honest code. 400 would
  claim we know the params were bad, which we do not. — Cost if wrong: a status-code change.
Tasks C2+C3: review dispatched, range 8fb80ba..9eef92f
Tasks C2+C3: review — spec ✅, quality APPROVED, 0 Critical / 0 Important.
  Highest-value check PASSED: enrichment's five user-supplied fields provably cannot be
  overridden — merge_operational_params returns params.merge(COMMON_OPERATIONAL_PARAMS) and
  nothing else for any job_type != 'diff_analysis'; the diff-only constants sit behind a
  `return merged unless job_type == 'diff_analysis'` guard. Backed by two unit tests plus an
  end-to-end HTTP check. Diff's threshold is keyed off antigenClass inside that same branch
  and never touches enrichment's.
  Unstubbed submission FAILS LOUDLY: WabiService#post calls raise_if_unstubbed_under_test!
  before any Net::HTTP call, raising LiveSubmitNotStubbed under RACK_ENV=test — the same
  pattern as BedExtensionResolver's LiveProbeNotStubbed. Guarded on the submission path only,
  which matches the stated risk, with --network none as backstop.
  Minors: (1) openapi.yaml documents only the 200 for POST /jobs/submit, no 502/503;
  (2) no test drives an unrecognized antigenClass through the DIFF_ANALYSIS_THRESHOLD fetch,
  which would surface today as an uncaught 500; (3) routes/jobs.rb:301 `case result[:error]`
  has no else, so an unexpected symbol would emit an empty 200; (4) report prose miscounts one
  file's tests (aggregate +32 is correct).
Ruling 19: fix Minors 1-3 in one small round rather than deferring. — Why: this is the job
  submission path — the one surface in this run where a mistake spends real compute on a
  shared DDBJ service. An unhandled branch that returns an empty 200 and an unexercised raise
  that 500s are exactly what should not be left on it, and all three edits are small and in
  files already open. Minor 4 (report prose) folds in free. — Cost if wrong: one extra small
  review cycle on a path that deserves it.
Tasks C2+C3: fix round 1/5 dispatched (resumed original implementer), FIX_BASE 9eef92f
Tasks C2+C3: fix round 1 implemented (commit 4f1e4c0; 212 runs (was 208); frontend 46/46;
  tsc 0; openapi re-validated). else-branch fails closed with 500; bare KeyError replaced by
  a named WabiService::UnknownAntigenClass naming the bad value and expected keys, tested at
  both service and route layers (route test confirms Sinatra propagates rather than swallows);
  openapi documents 502 and 503; report counts corrected.
Tasks C2+C3: scoped re-review dispatched (haiku, agent adc013bf87f39b50f), range 9eef92f..4f1e4c0
  Also asked it to confirm the two properties the prior review established did not regress:
  enrichment's five fields still never overridden, and unstubbed submission still raises.
Tasks C2+C3: fix round 1/5 (4 addressed, 0 open; commits 9eef92f..4f1e4c0)
  Both prior-review properties confirmed intact: enrichment's five fields still never
  overridden, unstubbed submission still raises. 502/503 not transposed in openapi.
Tasks C2+C3: complete (commits 8fb80ba..4f1e4c0, review clean)

Ruling 20: C4 also implements clearing the datasets when the experiment-type radio changes,
  not just per-genome state. — Why: D13's chosen option is worded "ゲノムごとに状態を分ける —
  現行版と同じ構造にする" (per-genome state — same structure as production), and production
  clears both axes: putDefaultTitles/eraseTextarea fire on the experiment-type radio as well
  as the genome tab. Leaving the experiment-type axis alone would let ChIP peak IDs be
  submitted as a Bisulfite-seq/DMR job, which is the same silent-wrong-result class as the
  genome axis. Flagged to Tazro in the report so he can veto — he picked among three options
  and the experiment-type axis was not offered separately.
  — Cost if wrong: one behaviour reverts to keeping data across a radio switch.
Task C4: dispatched, BASE 4f1e4c0 (carries the relocated unavailable-state UI per Ruling 17)
Task C4: implementer DONE_WITH_CONCERNS (commits ac2f341, b81e0d4; frontend 53/53 (was 46);
  backend 212/212; tsc 0; build ok; checklist 34/34).
  Concerns: (1) per-genome state is an in-memory JS map, not literal genome-prefixed DOM
  subtrees like production — same observable guarantee, flagged for veto; (2) the
  experiment-type clearing is flagged per Ruling 20 so Tazro can veto; (3) availability check
  FAILS OPEN (form stays usable) when the check itself errors; no browser was available to
  click through the unavailable UI.
Controller verification of (3) — restarted the container (it predated C3, so its Ruby lacked
  JOB_TYPE_BACKENDS) and checked live:
  /jobs/available?type=diff_analysis   -> {"backend":null,"available":false}
  /jobs/available?type=enrichment_analysis -> {"backend":"wabi","available":true}
  /status -> "diff_analysis":"unavailable", enrichment still "ok"
  (At session start this same endpoint reported "diff_analysis":"ok" while submission failed.)
  Rendered /diff_analysis: submit button disabled, notice reads "Diff analysis is currently
  unavailable: no compute backend is serving this job type right now. Please check back
  later.", genome tabs are hg38/mm10/rn6/dm6/ce11/sacCer3/TAIR12 (A1+A2 confirmed live).
Task C4: review dispatched, range 4f1e4c0..b81e0d4
Task C4: review — spec ✅, quality APPROVED, 0 Critical / 0 Important.
  Per-genome map covers every exit path: genome switching has exactly one trigger (the tab
  click -> 'genome-change'), no popstate/hashchange listener, and history.replaceState creates
  no back/forward entries. The listener reads the textareas' live .value at the exit event
  rather than a cached/debounced copy, so typed text, "Try example" fills and the radio clear
  are all captured.
  Fail-open judged the RIGHT call: /jobs/available is advisory, POST /jobs/submit re-checks
  server-side and returns 503, and the client surfaces that visibly — so failing open costs
  one retryable click during an outage, while failing closed would hide a working feature on
  a transient blip with no polling to un-hide it.
  Experiment-type clearing correct and properly scoped: clear() is a single-key write, so
  other genomes' stored datasets are untouched, with a dedicated regression test for it.
  Minor (DEFERRED to final review triage): createGenomeDatasetStore.get() returns the shared
  BLANK_DATASET_STATE by reference for an unvisited genome. No caller mutates it today, so it
  is latent, not live — a future mutating caller would corrupt the blank sentinel for every
  unvisited genome. One-line fix (return a fresh literal).
Task C4: complete (commits 4f1e4c0..b81e0d4, review clean)
Tasks C5+D2: dispatched as one batch, BASE b81e0d4
Tasks C5+D2: implementer DONE (commits 4a9d386 C5, 29698d0 D2; backend 213/213; frontend
  65/65; tsc 0; build ok; checklist 34/34).
  Flagged: (a) D2 needed a new opt-in `excludeTrackClassIds` option on FacetFilter, because
  that facet is SHARED between Peak Browser and Enrichment Analysis — a widening of shared
  API surface, handed to the reviewer to judge.
  (b) FOUND A FALSE GREEN IN THE TEST RUNNER: script/dev/test-frontend.sh's glob silently
  matched zero files once a test existed outside frontend/pages/, so it could report success
  while running nothing. This matters beyond its size — I wired that script into CI two tasks
  ago (Ruling 14), so a green CI run may have been meaningless in between. Same
  "passes while testing nothing" class as A2's network leak and the overflow script's missing
  precondition; third instance this run. Reviewer asked to confirm the fix FAILS LOUDLY on
  zero matches rather than merely matching more paths.
Tasks C5+D2: review dispatched (sonnet, agent a990679ed84c72eb7), range b81e0d4..29698d0
Tasks C5+D2: review — spec ✅, quality CHANGES NEEDED.
  Important (a): the Peak Browser / Enrichment Analysis separation is NOT integration-tested.
    facet-filter.test.ts only exercises the standalone excludeTrackClasses(items, ids) helper
    on synthetic data; nothing asserts enrichment-analysis.ts actually passes
    excludeTrackClassIds:['Annotation tracks'] or that peak-browser.ts does not. The only
    evidence for the real call sites is a manual live spot check.
  Important (b): the test-frontend.sh fix closes the diagnosed CAUSE but not the CLASS. The
    reviewer REPRODUCED it: an empty mapfile array expands to zero args and `node --test`
    with no targets prints "tests 0 / pass 0 / fail 0" and exits 0. No zero-count guard was
    added. So the runner can still report success while running nothing.
  Minor: excludeTrackClasses filters on it.id while production's rule is on label; harmless
    today because EXPERIMENT_TYPES gives Annotation tracks the same id and label.
  C5 semantics verified CORRECT on every named edge case, including deliberate abandonment
    (picking Random permutation while the gate is open hits the no-op branch and stashes
    nothing) and repeated open->close->open cycles (stash re-derived at each close, no drift),
    both with real tests. FacetFilter API widening judged the RIGHT call and the narrowest
    correct option — the "Annotation tracks" string lives only at the enrichment call site,
    it survives setGenome, and it scales to a third page without further component changes.
Tasks C5+D2: fix round 1/5 dispatched (resumed original implementer), FIX_BASE 29698d0
Tasks C5+D2: fix round 1 implemented (commit 804256e; backend 213/213; frontend 67/67; tsc 0;
  build ok; checklist 34/34). Zero-test guard added and verified to exit 1 against the real
  script when reproducing the reviewer's empty-match scenario; call-site config extracted as
  enrichmentFacetFilterOptions / peakBrowserFacetFilterOptions so the separation is testable;
  id-vs-label comment added.
Tasks C5+D2: scoped re-review dispatched (haiku, agent ac1f18ad8e49bc6a5), range 29698d0..804256e
  Asked specifically whether the extraction genuinely tests the CALL SITES or merely a new
  constant the call sites might not use — i.e. do both real FacetFilter.init invocations
  consume the extracted values.
Tasks C5+D2: fix round 1/5 (3 addressed, 0 open; commits 29698d0..804256e)
  Zero-test guard sits BEFORE node --test, checks ${#COMPILED_TESTS[@]} -eq 0, exits 1, and
  the report carries the real failing run. Both real FacetFilter.init call sites now consume
  the extracted option builders, so the tests bind to what actually runs rather than to a
  parallel constant.
Tasks C5+D2: complete (commits b81e0d4..804256e, review clean)
Tasks D1+D3: dispatched as one batch, BASE 804256e — LAST implementation dispatch
Tasks D1+D3: implementer DONE (commits 0914944 D1, 7410ce6 D3; test.sh 213/213;
  test-frontend 74/74 (+7); tsc 0; build ok; checklist 34/34; implementer's own 390px
  overflow check passed collapsed AND with all attributes expanded).
Controller live verification at 1440px against the running instance:
  headers now SRX, SRA, GEO, Genome, Track class, Track type, Cell type class, Cell type,
  Title, Attributes; SRX anchors carry target="_blank"; docScrollWidth == viewport (no page
  X scroll); Attributes renders "sample_name=DRS000203 · strain=C2C12 · sample comment=… ·
  cell type=…" so the raw __TAB__ separator does NOT leak to the user.
  COULD NOT verify a rendered GEO link — every sampled row had "-", and a direct GSM query
  returned nothing on the database this instance serves. Handed to the reviewer to confirm
  from code + tests for both the linked and the "-" case.
Tasks D1+D3: review dispatched (sonnet, agent ab5759bdcd6420357), range 804256e..7410ce6
Tasks D1+D3: review — spec ✅, quality APPROVED, 0 Critical / 0 Important.
  Escaping SAFE: title/attributes built with createElement + textContent only; formatAttributes
  is a pure string transform whose output only reaches textContent; no innerHTML in search.ts;
  the two <%== in search.erb are pre-existing partial includes on an unrelated path.
  GEO link path correct in BOTH branches, with tests: non-"-" ids get the encoded acc.cgi URL
  with target=_blank rel="noopener noreferrer"; "-" and "" yield null -> plain text, no anchor.
  CSS is GENUINE REUSE: #result-table-wrap now serves colo_result, target_genes_result and
  search from one rule (style.css:563-585); the target-genes-only rules under that id are
  class-qualified so they cannot leak into search.
  Minor (deferred): DOM wiring covered by manual verification only — but that matches the
  project-wide convention (no jsdom; every *.test.ts in the repo is pure-function-only), so
  it is a pre-existing limit, not a deviation this task introduced.
Tasks D1+D3: complete (commits 804256e..7410ce6, review clean)

=== ALL 15 TASKS COMPLETE ===
Final state at HEAD: 213 runs / 863 assertions / 0 failures; frontend 74/74; tsc exit 0;
ui-checklist 34/34; 30 commits in 0c66277..HEAD.

Ruling 21: the final whole-branch review covers THIS PLAN's range (0c66277..HEAD), not
  merge-base(master)..HEAD. — Why: sengu carries ~37 earlier commits from the separate UI
  parity effort, already reviewed in its own run; including them would bury this plan's work
  and re-litigate settled decisions. — Cost if wrong: the earlier branch work goes unreviewed
  by THIS pass, which it was never in scope for.

=== FINAL WHOLE-BRANCH REVIEW (opus, range 0c66277..7410ce6, 30 commits) ===
Verdict: issues to resolve first. 0 Critical, 4 Important, 10 Minor.
Cross-task interactions: CLEAN. All four multi-task files verified disjoint; D2's deletion did
  not move EXPERIMENT_TYPES.first (still 'Histone', still the 'undefined' fallback); C1->C2
  field sets provably disjoint; contain:layout paint safe on the search page too.
The two encodings: RUNTIME CORRECT EVERYWHERE — six paths traced end to end, nothing crosses,
  and n*10 is exactly -10*log10(1E-code), not a curve fit. BUT the PROSE is inverted at 4 sites.
Matrix view consistency: no drift; the six duplicated helpers are still byte-identical.
FOURTH AND FIFTH FALSE-GREENS FOUND:
  (4) frontend/tsconfig.json:21 now excludes **/*.test.ts, so `tsc --noEmit exit 0` no longer
      covers the ~1,100 lines of tests written this run. Cause is real (no @types/node) but
      the shrunken guarantee was never recorded.
  (5) CI runs the Ruby suite with FULL NETWORK ACCESS. Ruling 7 pinned --network none in
      script/dev/test.sh but NOT in .github/workflows/ci.yml, and DataProxy is the only one of
      four outbound services without raise_if_unstubbed_under_test!. api_test.rb:345,354 really
      do hit chip-atlas.dbcls.jp in CI; they pass only because upstream 404s, while the comment
      at :336-343 claims --network none prevents the call. Ruling 7 was half-executed.

Reviewer's corrections to MY rulings:
  - Ruling 7: sound but half-executed (see false-green 5).
  - Ruling 8: silently changed A3's stated Verify criterion. Under intersection semantics the
    stats gap is tab_only (annotation tracks PLUS genome-unconfirmed rows, 544 vs 541), and the
    test asserts tab_only==2 on fixtures, not the stats relationship. Better behaviour; I just
    never recorded that the original Verify no longer applies.
  - RULING 1 WAS FACTUALLY WRONG. I wrote that the colo result view "cannot be driven from the
    picker until B4 lands". It can: colo_result_by_genome splits cell_list "-" into ["-"], not
    [], so the picker offers a literal "-" and produces /colo_result?...&cell_type=- -> 404 ->
    error banner. Not a regression (colo 404'd before this branch too), but /colo is a LIVE
    NAVBAR ENTRY THAT FAILS ON EVERY QUERY, and my phrasing understated that.

Ruling 22: gate /colo behind the honest-unavailable pattern until B4 lands. — Why: Ruling 1 was
  wrong, so the page is reachable and 404s on every query. We just built and Tazro approved
  exactly this pattern for Diff Analysis (D12 "report availability honestly"); applying it to a
  function whose index is knowingly broken is the same principle, reuses existing code, and is
  one line to revert when B4 ships. Flagged prominently for veto.
  — Cost if wrong: B5's matrix is hidden a while longer; it is unreachable in practice anyway.
Final fix wave: applied (9 commits, 7410ce6..44f62bd; Ruby 215/215 (was 213); frontend 74/74;
  both tsc configs exit 0; build ok; checklist 34/34).
  Implementer concerns: (a) CI's new iptables-based isolation could not be verified against a
  real GitHub Actions run; (b) clean_old_genomes.rake's orphan guard was syntax-checked only,
  not run (the task is destructive); (c) item 6 is a FRONTEND-ONLY gate — the underlying
  colo_result_by_genome "-" -> ["-"] behaviour at lib/models/analysis.rb:88 is still present.
Controller live verification of the /colo gate: notice reads "Colocalization search is
  temporarily unavailable while the colocalization index is rebuilt upstream. Please check
  back later."; every search control is hidden (view-colo, download-tsv, download-gml,
  direction-track, direction-cell, primary-input, secondary-input). Only the navbar and the
  Tutorial dropdown remain. Correct.
Final fix wave: scoped re-review dispatched (sonnet, agent af3a70fe267067434), range
  7410ce6..44f62bd. Told it to INDEPENDENTLY VERIFY the corrected encoding wording rather than
  confirm it changed, and to judge whether the iptables isolation would fail loudly or
  silently on a real runner (a silent no-op would recreate the same false-green).
