# SDD ledger — follow-up work approved 2026-09-19

Two items deferred by the post-parity run, both put to the owner and both approved:
  F1. Colocalization Average column colouring — formula now known.
  F2. Target Genes server-side gene search — new capability, production lacks it.
Base: 0d6ad5e on sengu. Baseline 215 Ruby runs / 74 frontend / tsc clean / 34-34.

Task F1: implementer DONE (commit cebad50; Ruby 215/215; frontend 79/79 (+5); tsc both
  configs 0; build ok; checklist 34/34; no 390px overflow). Implementer correctly challenged
  my brief's prose and switched to floor + (a*1000)/9 ordering.
CONTROLLER ERROR, now corrected: my brief claimed the formula matched production on
  "all 1,000 rows with zero channel error". My verification script counted
  abs(diff) <= 1 as a match, so the real claim was "within +/-1", not exact. The
  implementer propagated my wrong claim into a code comment at colo-result.ts:203-207.
Brute-forcing stop set x rounding x scale ordering against all 1,000 production rows:
  blue@1 (STRING stops) / floor / (a*1000)/9   -> 501/1000 exact   <- as implemented
  blue@1 (STRING stops) / round / a*(1000/9)   -> 839/1000 exact   <- my original
  blue@0                / floor / (a*1000)/9   -> 999/1000 exact   <- CORRECT
  Every variant is within +/-1 on every channel of every row, so none is visibly wrong.
The real rule: the Average ramp starts BLUE AT 0, not blue at 1. The STRING ramp reserves
  0 for "no data" (gray); the Average column has no such sentinel. The single residual row
  (SRX347426, avg 2.4) is a float artifact: blue computes to 237.999... -> floor 237 vs
  production's 238. Scale ordering makes no difference once the stop set is right.
Task F1: fix round 1/5 dispatched (resumed implementer)
Task F1: fix round 1 implemented (commit c4a2a0e; Ruby 215/215; frontend 80/80; tsc both 0;
  build ok; checklist 34/34). Implementer honestly noted it did NOT independently re-run the
  1000-row count and was relying on my script — which had already been wrong once.
CONTROLLER INDEPENDENT VERIFICATION of the SHIPPED code: bundled frontend/pages/colo-result.ts
  with esbuild, imported the real averageToRgb, ran it against all 1,000 (average, bgcolor)
  pairs scraped from production's own hg38/colo/STAT3.Blood.html:
    exact 999/1000, within +/-1 1000/1000
    sole mismatch SRX347426, avg 2.4, production [0,255,238] vs ours [0,255,237]
  — exactly the float artifact predicted. The corrected rule is confirmed against the real
  implementation, not against my earlier reasoning.
Task F1: re-review dispatched (read-only, safe to overlap with F2's implementer)
Task F2: dispatched, BASE c4a2a0e
Task F1: review — spec ✅, quality APPROVED. Comment confirmed honest (no "zero channel
  error" left; states 999/1000 exact, all within +/-1, names the SRX347426 artifact).
  COLOR_STOPS/scoreToRgb untouched; a separate AVERAGE_COLOR_STOPS was added instead.
  Bottom-of-range covered (averageToRgb(0.05) -> #0005ff) plus the average==0 -> gray boundary.
  NOTE: the reviewer hand-computed #0005f9 for 0.05 and said it was "trusting the report"
  over its own arithmetic. Controller checked the SHIPPED function: #0005ff is correct — in
  the [0=blue, 250=cyan] segment blue stays 255 and green rises; the reviewer had interpolated
  blue downward. Spot values from the real code: 0 -> #808080, 0.05 -> #0005ff,
  2.25 -> #00ffff, 3.0 -> #00ffaa, 3.866667 -> #00ff47, 9 -> #ff0000.
Task F1: complete (commits 0d6ad5e..c4a2a0e, review clean)

Task F2: implementer DONE (commits 17335c9 API, c4bba94 UI; Ruby 227/227 (was 215);
  frontend 83/83; tsc both 0; build ok; checklist 34/34; live headless check against real
  mm10/Stat3 13,459-gene data).
Controller live verification against the running instance:
  unfiltered total 13,459, top gene Stat3.
  q=Socs3 -> total 1; q=Bcl6 -> total 2 (Bcl6, Bcl6b, so substring not prefix); q=zzzqqq -> total 0.
  FILTER-BEFORE-SLICE CONFIRMED: Zbtb16 sits at unfiltered rank 9000 (page 91 of 135); with
  q=Zbtb16 it returns total=1, offset=0, row 1 — i.e. the whole set is filtered, not the page.
  CACHE NOT KEYED ON THE QUERY: four different queries all ~30ms after one warm-up. Re-parsing
  the 4.1 MB matrix per query would be seconds, so the parsed matrix is being reused.
  Case-insensitive confirmed (Zbtb16 and zBTB16 both total 1).
Task F2: review dispatched, range c4a2a0e..c4bba94
Task F2: review — spec ✅, quality CHANGES NEEDED (1 Important, 1 Minor).
  The two empty states are separated STRUCTURALLY, not just by wording: "no genes match" only
  fires on a 200 with total==0 inside the try branch, while "this combination has no data"
  lives entirely in the catch branch and swaps to #error-state. Server-side, result() checks
  load() for nil BEFORE applying q, so a genuinely-absent combination 404s whether or not a
  query is active — the overlap case cannot be misreported. Exactly what the brief demanded.
  Stale responses handled by a generation counter checked after both the await and in the
  catch, not merely a debounce timer — covers query, sort, distance and pagination.
  Escaping safe (textContent only; encodeURIComponent on the URL).
  Important: a long unbroken query echoed into #row-count breaks the 390px constraint. The
  reviewer reasoned it from the CSS but had no instance to confirm.
CONTROLLER CONFIRMED IT LIVE at a true 390px viewport with a 300-char unbroken query:
  documentElement.scrollWidth 390 -> 2031, #row-count right edge 2031, input has no maxlength.
  Real defect, not theoretical.
Task F2: fix round 1/5 dispatched (resumed implementer), FIX_BASE c4bba94
Task F2: fix round 1 implemented (commit dd71af2; Ruby 227/227; frontend 83/83; tsc 0;
  build ok; checklist 34/34; measure-target-genes-overflow.mjs extended to 5 cases, the new
  one verified failing on pre-fix CSS and passing after).
CONTROLLER INDEPENDENT RE-MEASUREMENT at a true 390px viewport, 300-char unbroken query:
  scrollWidth 2031 -> 390, pageScrollsX false, #row-count right edge 378 (inside viewport),
  maxlength="200" served. Note .value assignment bypasses maxlength, so the full 300 chars
  were present and it still did not overflow — the CSS carries it, not just the cap.
  (Two false alarms along the way, both mine: the container had cached the ERB, and then the
  container had gone away entirely. Neither was a code defect.)
Task F2: scoped re-review dispatched, range c4bba94..dd71af2
Task F2: re-review — ADDRESSED, no new breakage. Regression case judged sound (isolates
  #row-count, bypasses maxlength with a 300-char programmatic write, waits past the debounce,
  confirmed failing pre-fix). #row-count also exists on colo_result.erb as a block element,
  where min-width:0 is inert — no cross-page regression.
  Two Minors, both instances of classes I have corrected repeatedly this run:
  (a) the CSS comment claims "the identical treatment task D1 established", but D1's rule is
      max-width + overflow-wrap on table cells while this is min-width:0 + overflow-wrap on a
      flex item — the same principle, adapted, not identical. An overclaiming comment.
  (b) maxlength="200" in the ERB and MAX_QUERY_LENGTH = 200 in target_genes_tsv.rb are two
      independent literals that can silently drift.
Ruling 23: fix both rather than defer, despite being Minor and despite this being the last
  item. — Why: (a) is the same defect I spent a round correcting in F1 (a comment stating
  something stronger than the truth, which the next maintainer trusts), and (b) is a
  two-literals-drift of exactly the kind the threshold/file-code hazard taught this codebase
  to avoid. Both are about two lines. — Cost if wrong: a trivial diff on the last commit.
Task F2: fix round 2/5 dispatched, FIX_BASE dd71af2
