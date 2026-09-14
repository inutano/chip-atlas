# ChIP-Atlas UI Parity Audit — old vs. sengu

**Date:** 2026-09-14
**Compared:** `https://chip-atlas.org` (production, Bootstrap 3.2.0) vs. the `sengu` branch running locally on `:9292` (Bootstrap 5)
**Method:** headless Chromium screenshots at 1440 px, plus direct comparison of served HTML and CSS from both apps.
**Goal of the follow-up work:** make the rebuilt UI look and behave as close to production as possible.

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

### 1. Navbar — cosmetic
- Brand is a five-pointed star SVG; should be the mountain/triangle glyph.
- Nine link glyphs missing.
- Production wraps `navbar-form` to a second row (ID field below the links); sengu keeps Search + ID + Go inline on one row.
- sengu adds a **Demo** item production does not have.

### 2. Page header — cosmetic
- No `.page-header` bottom rule (BS5 dropped the class, nothing replaced it).
- No `fa-mountain` glyph in `h1`.

### 3. Container width — cosmetic
- 1170px → 1320px. Everything sits ~75px wider on each side.

### 4. Homepage feature cards — cosmetic
- Grey `.jumbotron` (no border) → white `.card` with `#dee2e6` border.
- 70px monochrome glyph → colour emoji. **Peak Browser and Dataset Search currently share the same magnifier emoji**; production uses glasses and magnifier respectively.
- Card title `h3` → `h5`.
- `.label.label-primary` → `.badge.bg-primary` — visually near-identical, no action needed.

### 5. Genome tabs — cosmetic
- Shows `hg38`; production shows `H. sapiens (hg38)`. `/api/genomes` already returns the full label; `frontend/components/genome-tabs.ts:57` prints `code` instead.

### 6. Buttons — cosmetic
- Production uses two solid `btn-primary btn-lg btn-block`; sengu makes the second `btn-outline-primary`.
- "Download BED file" shortened to "Download BED".
- `Error connecting to IGV?` link missing.

### 7. Peak Browser — interaction model
- Five `.panel-default` boxes across three columns → one card titled "Filter".
- `<select size="8">` list boxes → collapsed `<select>`.
- `input.typeahead` ("type to search") above Track type and Cell type gone from the page.
- Numbered headings (1., 2., 3.) gone — the taught workflow sequence is lost.
- Tutorial dropdown (PDF / Movie / 統合TV) missing.

### 8. Enrichment Analysis — interaction model
- Six numbered panels (3×2) → four (2×2); steps 1–3 merged into one "Filter" card.
- Renumbering breaks the PDF manual's step references.
- Missing: seven ⓘ info buttons, "Try with example", "Choose local file" caption, "Estimated run time", "node status (epyc.q)" link.
- Production seeds titles with `My project` / `Dataset A` / `Dataset B`; sengu leaves them empty.
- sengu adds two disabled radios ("gene-list mode only") — an improvement; keep.

### 9. Dataset Search — interaction model
- Production opens as a browsable DataTables view of all 432,319 rows; sengu shows nothing until queried.
- Missing: Show-N-entries, Copy / TSV export, "Showing x to y of N" counter, per-column sorting, Simple/Detailed tabs, numbered pagination.
- **Decision taken:** restore the default listing only. No DataTables, no column sorting, no export. `/api/search` already paginates server-side.

### 10. Target Genes — interaction model
- Antigen `<select size="8">` list box gone; only the search input remains.
- Panels went content-sized (`col-md-3`) → half-width, leaving two mostly-empty boxes.
- `±1k / ±5k / ±10k` → `±1 kb / ±5 kb / ±10 kb`.

### 11. Experiment detail — structural
- **Experiment Comparative Profile section absent entirely.**
- Eight heading glyphs missing; sub-headings dropped from `h4` weight to body text.
- "Where can I get the processing logs?" → "Pipeline docs", lost its external-link icon.
- Single-assembly pipeline block is correct — hg19 was intentionally dropped.

### 12–13. Footer, colour tokens, markdown pages — match
- Footer rules are already ported verbatim. `.markdown-content` mirrors `.publication_list`. No action beyond the colour-token corrections above.

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

## Out of scope / open questions

- Whether **Demo** belongs in the production navbar.
- Whether the **Simple / Detailed search** tab pair returns (decision: no, for now).
- `/api/remote_url_status` has no caching and no `Cache-Control` (open issue #223). Rebuilding the Comparative Profile will make it live traffic for the first time — settle the caching question as part of that task.
