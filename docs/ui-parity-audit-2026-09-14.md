# ChIP-Atlas UI Parity Audit — old vs. sengu

**Date:** 2026-09-14
**Compared:** `https://chip-atlas.org` (production, Bootstrap 3.2.0) vs. the `sengu` branch running locally on `:9292` (Bootstrap 5)
**Method:** headless Chromium screenshots at 1440 px, plus direct comparison of served HTML and CSS from both apps.
**Goal of the follow-up work:** make the rebuilt UI look and behave as close to production as possible.

---

## Status (updated 2026-09-14)

Implemented by `docs/superpowers/plans/2026-09-14-ui-parity-with-production.md`.
Parity checklist score: **35/35**. Remaining intentional differences are
listed under "Out of scope / open questions". Two gaps were found during
Task 19's final evaluation that are **not** covered by the checklist and are
**not** resolved — Colo's missing list box/heading relabel and Diff
Analysis's missing description-panel affordances (component deltas #14 and
#15). See "Added during Task 19" under open questions for detail.

---

## Verdict

The shell survived the rebuild; the instruments did not. Navbar geometry, footer, page titles and the blue accent are all recognisably the same. What changed is every control a researcher touches: the old app's scrolling list boxes, type-to-search fields and numbered panels became five stacked dropdowns.

Thirteen components audited — 3 already match, 6 need cosmetic work, 4 changed interaction model.

---

## Root causes

Every difference traces to one of three dependency swaps. None are arbitrary design choices.

| Swap | Consequence |
|---|---|
| Bootstrap 3.2 → Bootstrap 5 | BS5 deleted `.panel`, `.jumbotron`, `.page-header`, `.label`, `.btn-block`. Each was replaced with `.card` or dropped. |
| Font Awesome 5 → nothing | 27 distinct glyphs used in production, none in the rebuild. `public/icons/` holds only `.gitkeep`; `style.css` still has a dead `.nav-link i` rule. The homepage substitutes emoji. |
| jQuery plugins → TypeScript | Typeahead, Flexselect and DataTables drove the old controls. `Autocomplete` and `FacetFilter` replaced them but render collapsed `<select>` elements instead of `size="8"` list boxes. |

---

## Reference values (production, Bootstrap 3.2.0)

These are the exact values to target. **Two are currently wrong in `public/css/style.css`.**

| Token | Production value | Current sengu value |
|---|---|---|
| Primary / link colour | `#428bca` | `#337ab7` ❌ (that is BS 3.3, not 3.2) |
| `.btn-primary` border | `#357ebd` | `#2e6da4` ❌ |
| Body font family | `"Helvetica Neue", Helvetica, Arial, sans-serif` | `system-ui, -apple-system, …` ❌ |
| Body font size | `14px` | `0.95rem` (15.2px) ❌ |
| Body line-height | `1.42857143` | BS5 default `1.5` |
| Body text colour | `#333` | BS5 default `#212529` |
| Navbar background | `#222` | `bg-dark` = `#212529` |
| Navbar active item | `#080808` | BS5 default |
| Navbar link text | `white` (forced by `.navbar-inverse a`) | `rgba(255,255,255,.55)` ❌ (BS5 `navbar-dark` default, visibly dim) |
| Container max-width | `1170px` (at ≥1200px) | `1320px` (BS5 xxl) ❌ |
| Body padding-top | `70px` | `70px` ✓ |
| Navbar min-height | `50px` | `50px` ✓ |

### Component CSS to reproduce

```css
.page-header { padding-bottom: 9px; margin: 40px 0 20px; border-bottom: 1px solid #eee; }

.jumbotron   { padding: 30px; margin-bottom: 30px; color: inherit; background-color: #eee; }

.panel       { margin-bottom: 20px; background-color: #fff; border: 1px solid transparent;
               border-radius: 4px; box-shadow: 0 1px 1px rgba(0,0,0,.05); }
.panel-default > .panel-heading { color: #333; background-color: #f5f5f5; border-color: #ddd; }
.panel-heading { padding: 10px 15px; border-bottom: 1px solid transparent;
                 border-top-left-radius: 3px; border-top-right-radius: 3px; }

.label       { display: inline; padding: .2em .6em .3em; font-size: 75%; font-weight: 700;
               line-height: 1; color: #fff; text-align: center; white-space: nowrap;
               vertical-align: baseline; border-radius: .25em; }
.label-primary { background-color: #428bca; }

.nav-tabs > li.active > a { color: #555; background-color: #fff;
                            border: 1px solid #ddd; border-bottom-color: transparent; }
```

---

## Icon inventory

27 distinct Font Awesome 5 Free glyphs, by usage count across all production pages:

| Glyph | Uses | Where |
|---|---|---|
| `fa-mountain` | 16 | navbar brand, every page `h1` |
| `fa-search` | 10 | navbar |
| `fa-info-circle` | 10 | ⓘ buttons on analysis pages |
| `fa-hand-holding-heart` | 10 | navbar + homepage card (Enrichment Analysis) |
| `fa-glasses` | 10 | navbar + homepage card (Peak Browser) |
| `fa-compress-arrows-alt` | 10 | navbar + homepage card (Colo) |
| `fa-bullseye` | 10 | navbar + homepage card (Target Genes) |
| `fa-book` | 10 | navbar (Publications) |
| `fa-balance-scale-left` | 10 | navbar + homepage card (Diff Analysis) |
| `fa-robot` | 9 | navbar (Agents) |
| `fa-github` (brands) | 9 | navbar (Docs) |
| `fa-question-circle` | 6 | Tutorial dropdown buttons |
| `fa-spinner` | 4 | loading indicators on `/view` |
| `fa-download` | 3 | `/view` Download menu |
| `fa-dna` | 3 | `/view` genome sub-headings |
| `fa-chart-line` | 3 | `/view` Read and Peak Distribution |
| `fa-project-diagram` | 2 | `/view` Correlation-Based Clustering |
| `fa-external-link-alt` | 2 | `/view` Link Out, processing-logs link |
| `fa-user-edit` | 1 | `/view` Original Experimental Metadata |
| `fa-tag` | 1 | `/view` Antigen Information |
| `fa-server` | 1 | `/view` Sequencing Platform |
| `fa-microscope` | 1 | `/view` Cell Type Information |
| `fa-flask` | 1 | `/view` Sample Attributes |
| `fa-file-alt` | 1 | `/view` page title |
| `fa-eye` | 1 | `/view` Visualize menu |
| `fa-cogs` | 1 | `/view` Read Processing Pipeline |
| `fa-chart-bar` | 1 | `/view` Experiment Comparative Profile |

Also: `fa-hourglass-half` style glyph used for "Sample Information Curated by ChIP-Atlas" (rendered as an hourglass in screenshots) — confirm exact name when building the sprite.

**Licensing:** Font Awesome Free icons are CC BY 4.0. Vendoring a subset sprite requires attribution — add a comment in the sprite file and a line in the footer or `LICENSE.txt`. Production already ships Font Awesome, so this introduces no new obligation.

---

## Navbar abbreviations (already implemented, keep)

Below 1375px production swaps full labels for: `PB`, `EA`, `DA`, `TG`, `Colo`, `Pub`, `API`, `Doc`, `?`. The `.full-text` / `.abbrev-text` mechanism is already ported to `public/css/style.css` and works.

---

## Component deltas

### 1. Navbar — cosmetic — **RESOLVED** (Demo item: INTENTIONAL, see open questions)
- Brand is a five-pointed star SVG; should be the mountain/triangle glyph. — fixed, `chip-atlas.svg#mountain`.
- Nine link glyphs missing. — fixed, all ten navbar icon markers pass (`script/dev/parity-markers.txt`).
- Production wraps `navbar-form` to a second row (ID field below the links); sengu keeps Search + ID + Go inline on one row. — fixed via `.navbar-right-stack` (column layout, Search above ID form).
- sengu adds a **Demo** item production does not have. — still present; see open questions.

### 2. Page header — cosmetic — **RESOLVED**
- No `.page-header` bottom rule (BS5 dropped the class, nothing replaced it). — restored in `public/css/style.css`.
- No `fa-mountain` glyph in `h1`. — present on every page verified (Peak Browser, Target Genes, Colo, Diff Analysis, Enrichment Analysis, home).

### 3. Container width — cosmetic — **RESOLVED**
- 1170px → 1320px. Everything sits ~75px wider on each side. — fixed, `container pinned to Bootstrap 3 width` marker passes.

### 4. Homepage feature cards — cosmetic — **RESOLVED**
- Grey `.jumbotron` (no border) → white `.card` with `#dee2e6` border. — reverted to `.jumbotron`, marker passes.
- 70px monochrome glyph → colour emoji. **Peak Browser and Dataset Search currently share the same magnifier emoji**; production uses glasses and magnifier respectively. — fixed, contact sheet confirms distinct glasses/magnifier per card.
- Card title `h3` → `h5`. — verified `h3` in rendered markup.
- `.label.label-primary` → `.badge.bg-primary` — visually near-identical, no action needed. — unchanged, no action needed.

### 5. Genome tabs — cosmetic — **RESOLVED**
- Shows `hg38`; production shows `H. sapiens (hg38)`. `/api/genomes` already returns the full label; `frontend/components/genome-tabs.ts:57` prints `code` instead. — fixed, contact sheets show full label on every analysis page.

### 6. Buttons — cosmetic — **RESOLVED**
- Production uses two solid `btn-primary btn-lg btn-block`; sengu makes the second `btn-outline-primary`. — fixed, both View on IGV and Download BED file render solid.
- "Download BED file" shortened to "Download BED". — fixed, full label marker passes.
- `Error connecting to IGV?` link missing. — fixed, marker passes and visible on contact sheet.

### 7. Peak Browser — interaction model — **RESOLVED**
- Five `.panel-default` boxes across three columns → one card titled "Filter". — fixed, three-column panel grid restored (verified at 400/768/1024/1440px, no horizontal overflow at any width).
- `<select size="8">` list boxes → collapsed `<select>`. — fixed, all five facets render as real `size="8"` list boxes, confirmed keyboard-reachable with visible focus.
- `input.typeahead` ("type to search") above Track type and Cell type gone from the page. — fixed, both typeahead inputs present and keyboard-reachable.
- Numbered headings (1., 2., 3.) gone — the taught workflow sequence is lost. — fixed, markers pass.
- Tutorial dropdown (PDF / Movie / 統合TV) missing. — fixed, present and keyboard-reachable.
- **New finding (Task 19):** the "3. Threshold for Significance" list box displayed raw file-suffix values (`05`,`10`,`20`,`50`) instead of production's `-10*Log10(Q)` labels (`50`,`100`,`200`,`500`), contradicting the page's own ⓘ tooltip text ("If 50 is set here, peaks with Q value < 1E-05..."). Fixed in this task — `frontend/components/facet-filter.ts` now formats the label via `qvalLabel()` while keeping the underlying option value unchanged. Affects both Peak Browser and Enrichment Analysis (shared `FacetFilter` component).

### 8. Enrichment Analysis — interaction model — **RESOLVED** (run-time estimate: INTENTIONAL, see open questions)
- Six numbered panels (3×2) → four (2×2); steps 1–3 merged into one "Filter" card. — fixed, six numbered panels restored (contact sheet confirms 1–6).
- Renumbering breaks the PDF manual's step references. — resolved by the above.
- Missing: seven ⓘ info buttons, "Try with example", "Choose local file" caption, "Estimated run time", "node status (epyc.q)" link. — fixed (Task 14), all present and keyboard-reachable; "Estimated run time" itself stays an em-dash, see open questions.
- Production seeds titles with `My project` / `Dataset A` / `Dataset B`; sengu leaves them empty. — fixed, contact sheet confirms seeded values.
- sengu adds two disabled radios ("gene-list mode only") — an improvement; keep. — kept.

### 9. Dataset Search — interaction model — **INTENTIONAL**
- Production opens as a browsable DataTables view of all 432,319 rows; sengu shows nothing until queried. — fixed, sengu now lists all experiments by default.
- Missing: Show-N-entries, Copy / TSV export, "Showing x to y of N" counter, per-column sorting, Simple/Detailed tabs, numbered pagination. — scoped out; see open questions (Show-N-entries and Simple/Detailed tabs explicitly declined).
- **Decision taken:** restore the default listing only. No DataTables, no column sorting, no export. `/api/search` already paginates server-side.

### 10. Target Genes — interaction model — **RESOLVED** (hg38 empty data: INTENTIONAL/upstream gap, see open questions)
- Antigen `<select size="8">` list box gone; only the search input remains. — fixed, list box restored (empty for hg38 only, due to the metadata gap logged below).
- Panels went content-sized (`col-md-3`) → half-width, leaving two mostly-empty boxes. — fixed, contact sheet shows matching panel proportions.
- `±1k / ±5k / ±10k` → `±1 kb / ±5 kb / ±10 kb`. — fixed, labels now read `±1k / ±5k / ±10k` verbatim.

### 11. Experiment detail — structural — **RESOLVED**
- **Experiment Comparative Profile section absent entirely.** — fixed (commit `5f3583f`), section restored with Read/Peak Distribution and Correlation-Based Clustering, `/api/remote_url_status`-driven, contact sheet is a near-pixel match.
- Eight heading glyphs missing; sub-headings dropped from `h4` weight to body text. — fixed, all glyphs present on contact sheet.
- "Where can I get the processing logs?" → "Pipeline docs", lost its external-link icon. — fixed, icon present.
- Single-assembly pipeline block is correct — hg19 was intentionally dropped. — unchanged, confirmed intentional.

### 12–13. Footer, colour tokens, markdown pages — match — **RESOLVED**
- Footer rules are already ported verbatim. `.markdown-content` mirrors `.publication_list`. No action beyond the colour-token corrections above.

### 14. Colo — interaction model — **NOT RESOLVED (new finding, Task 19)**
- Production's "2. Choose Antigen" / "3. Choose Cell Type Class" panels (headings are relabelled by JS depending on search direction — raw markup says "Primary Type"/"Secondary Type", `colo.js:74-78` rewrites them) each pair a typeahead input with a real `<select size="8">` list box populated with the full antigen/cell-type list (`hg38PrimaryPanel-select`, confirmed via production's raw HTML).
- sengu's `frontend/pages/colo.ts` calls `Autocomplete.init(pInput, [], ...)` / `Autocomplete.init(sInput, [], ...)` **without** the `pairedList` option, so panels 2 and 3 are typeahead-only — no list box, and the panel headings never change from the generic "Choose Primary Type" / "Choose Secondary Type" regardless of search direction.
- This is not covered by any marker in `script/dev/parity-markers.txt`, so the 35/35 checklist score does not catch it. Flagged here rather than fixed in Task 19 because it needs new markup (a list-box mount point per panel) and heading-relabel logic, not a one-line change — treat as unfinished work from the "Convert Diff Analysis, Target Genes and Colo to panel layout with list boxes" task.

### 15. Diff Analysis — interaction model — **NOT RESOLVED (new finding, Task 19)**
- Production's "4. Analysis description" panel (sengu: "4. Description") has three ⓘ info buttons (`hg38ProjectDesc`, `hg38DataSetADesc`, `hg38DataSetBDesc`), seeds the three title fields with `My project` / `dataset A` / `dataset B`, and panels 2/3 each carry a "Try with example" link and a "node status (epyc.q)" link next to "Estimated run time" — confirmed in production's raw HTML.
- sengu's `/diff_analysis` has none of these: no ⓘ buttons, empty title fields, no "Try with example" links, no "node status" link (verified via `curl http://localhost:9292/diff_analysis`).
- This is the same restoration Task 14 did for Enrichment Analysis's identical panel, just never applied to Diff Analysis's equivalent panel. Not covered by any parity marker, so 35/35 does not catch it either. Flagged rather than fixed here — same reasoning as Colo above.

---

## Comparative Profile — asset contract (verified 2026-09-14)

The section is driven entirely by pre-rendered assets on the data server. All four probes returned 200:

| Asset | URL pattern |
|---|---|
| Distribution PNG | `https://chip-atlas.dbcls.jp/data/<genome>/distribution/png/<SRX>.dist.png` |
| Correlation PNG | `https://chip-atlas.dbcls.jp/data/<genome>/correlation/png/<SRX>.cor.png` |
| Correlation TSV | `https://chip-atlas.dbcls.jp/data/<genome>/correlation/tsv/<genome>__x__<track_subclass>__x__<cell_type_subclass>.tsv` |

Spaces in the track/cell-type segments become underscores.

Production renders the panel hidden, probes each URL from the client, and reveals only what exists. **This is exactly what `/api/remote_url_status` was built for** — the endpoint exists in the rebuild, is declared in `frontend/api/client.ts:415`, and is currently called by nothing. Rebuilding this section gives it its purpose back.

Caveat: the PNGs carry `Last-Modified` dates of Sept 2025. They are published and current for existing experiments, but confirm the pipeline still regenerates them before promising the section stays fresh.

---

## Follow-ups left open after the parity work (2026-09-14)

Three known differences remain after the implementation. None is a regression; each was weighed and deliberately left.

- **Diff Analysis panel 2/3 headings.** They read "2. Dataset A (Experiment IDs)" / "3. Dataset B (Experiment IDs)"; production's convention (already used on Enrichment Analysis) is "Enter dataset A/B". Two strings on one page.
- **`/api/remote_url_status` still caches a genuine upstream 5xx for an hour.** The reported bug — a transient *network* failure being cached and hiding the Comparative Profile — is fixed; the rescue path no longer sets `cache_control`. The narrower remaining case is a reachable server that returns 500: that response is exception-free, so it still gets the hour-long public cache. Tightening the header to 2xx/4xx only would close it.
- **Tutorial button placement.** Production anchors it top-right beside the page title; the rebuild places it below the genome tabs. Functionally identical, visually offset.

## Out of scope / open questions

- **Target Genes has no human data in the current metadata.** `analysisList.tab` dated 2026-09-09 contains no `hg38` or `hg19` rows at all — only mm9/mm10, dm3/dm6, ce10/ce11, sacCer3, rn6 and TAIR12. The loader reads the file correctly; the rows are simply absent. The underlying data files DO exist (`https://chip-atlas.dbcls.jp/data/hg38/target/CTCF.1.tsv` returns 200) and production offers hg38 on that page, so this is an upstream metadata gap that would ship an empty Target Genes for the most-used organism. Belongs with the data-regeneration work, not with UI parity.

- **Enrichment Analysis run-time estimate has no backend formula.** The affordance was restored in Task 14 and is wired to `POST /jobs/estimated_time`, but that endpoint only defines formulas for `dmr` and `diffbind` (Diff Analysis job types) — see `routes/jobs.rb:102`. Production shows "13 mins" on this page. Restoring a real number needs a formula derived from actual EA job durations, which is backend work requiring domain input. The label currently renders an em-dash rather than a fabricated figure.

- Whether **Demo** belongs in the production navbar.
- Whether the **Simple / Detailed search** tab pair returns (decision: no, for now).
- `/api/remote_url_status` has no caching and no `Cache-Control` (open issue #223). Rebuilding the Comparative Profile will make it live traffic for the first time — settle the caching question as part of that task.

### Added during Task 19 (final evaluation)

- **Colo's "Choose Primary/Secondary Type" panels lack production's paired list box and dynamic heading relabel.** Production pairs each typeahead with a real `<select size="8">` (`hg38PrimaryPanel-select` etc., populated with the full antigen/cell-type list) and relabels the two panel headings to "Choose Antigen" / "Choose Cell Type Class" (or the reverse) once a genome and direction are picked (`colo.js:74-78`). sengu's `frontend/pages/colo.ts` calls `Autocomplete.init` without the `pairedList` option, so both panels are typeahead-only with generic, static headings. Not covered by `script/dev/parity-markers.txt`, so the 35/35 score does not catch it. See component delta #14 above. Needs a follow-up task (new list-box mount markup + heading-relabel logic), not fixed here.

- **Diff Analysis's "Analysis description" panel is missing everything Task 14 restored for Enrichment Analysis's identical panel.** No ⓘ info buttons on the three title fields, no seeded `My project` / `dataset A` / `dataset B` defaults, no "Try with example" links on Dataset A/B, no "node status (epyc.q)" link, and the panel heading itself reads "4. Description" instead of production's "4. Analysis description" — all confirmed against production's raw HTML. Not covered by any parity marker. See component delta #15 above. Needs a follow-up task; same restoration pattern as Task 14, just never applied here.

- **Peak Browser / Colo / Diff Analysis / Enrichment Analysis genome tabs offer fewer assemblies than production for some species, and one production doesn't have at all.** Production's Peak Browser lists `hg38, hg19, mm10, mm9, rn6, dm6, dm3, ce11, ce10, sacCer3` (legacy builds included) and has no Arabidopsis tab. sengu's `/api/genomes` returns `hg38, mm10, rn6, dm6, ce11, sacCer3, TAIR10` — current builds only, plus `A. thaliana (TAIR10)`, which production's Peak Browser does not offer at all. This tracks with the already-documented decision to drop hg19 as legacy (component delta #11), so it reads as intentional rather than a defect, but it was not previously written down for Peak Browser/Colo/Diff Analysis/Enrichment Analysis specifically. Flagging so it isn't mistaken for an oversight.

- **A `chromium --headless --screenshot=...` CLI capture (the method `script/dev/ui-parity.sh` and the Step 2 brief command both use) is not fully reliable evidence on its own.** During this task it under-rendered the navbar toggler icon at narrow widths (fixed via `Emulation.setDeviceMetricsOverride` + `Page.captureScreenshot` over the DevTools Protocol, which confirmed the real page has no horizontal overflow and the toggler renders correctly and reachably at 400px). A reviewer re-running `script/dev/ui-parity.sh` and seeing a blank/odd navbar corner at narrow widths should not read that as a regression without double-checking through CDP or a real browser first.
