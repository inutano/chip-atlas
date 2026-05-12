# ChIP-Atlas Frontend Rebuild Design

**Date:** 2026-05-12
**Author:** Tazro Ohta + Claude
**Status:** Design approved, ready for implementation plan
**Prerequisite:** Backend (Phase 1) is complete — all `/api/*` endpoints working, 50 tests passing.

---

## Goal

Rebuild the ChIP-Atlas frontend with modern tooling while preserving the exact same UI appearance and user workflows. Users should not notice anything changed except faster page loads and a better search experience.

---

## Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | CSS framework | **Bootstrap 5** — self-hosted, vendored in public/. Upgrade from Bootstrap 3. |
| 2 | JS framework | **None** — vanilla TypeScript compiled by esbuild. No React/Vue/jQuery. |
| 3 | Template engine | **ERB** — Ruby stdlib, zero dependencies, 10-year stability. |
| 4 | Icons | **Bootstrap Icons** — SVG sprite, self-hosted. Replaces Font Awesome 5. |
| 5 | Build tool | **esbuild** — compiles TypeScript to JS bundles. Zero-config, <100ms builds. |
| 6 | Search | **Server-side** via `/api/search` with FTS5 pagination. No more 200MB JSON in browser. |
| 7 | Autocomplete | **Custom TypeScript** component. Replaces Typeahead.js + Flexselect + LiquidMetal. |
| 8 | Data tables | **Plain HTML tables** with sort/search in TypeScript. No DataTables library. |
| 9 | Colo/Target Genes results | **In-app rendering** — fetch JSON from API, render table. No redirect to external HTML. |
| 10 | Navigation | **Same navbar** as current — Bootstrap 5 navbar with logo, page links, experiment search. |

---

## Architecture

```
Browser
├── Bootstrap 5 CSS + style.css (overrides)
├── Bootstrap 5 JS (bundle, for dropdowns/tabs/modals)
├── TypeScript (esbuild-compiled to public/js/)
│   ├── api/client.ts          — Typed fetch wrappers for all endpoints
│   ├── components/
│   │   ├── genome-tabs.ts     — Shared genome tab switcher
│   │   ├── facet-filter.ts    — Cascading dropdown filters
│   │   ├── autocomplete.ts    — Typeahead replacement
│   │   └── job-tracker.ts     — Job status polling + live clock
│   └── pages/
│       ├── peak-browser.ts
│       ├── enrichment-analysis.ts
│       ├── diff-analysis.ts
│       ├── target-genes.ts
│       ├── colo.ts
│       ├── experiment.ts
│       ├── search.ts
│       ├── colo-result.ts
│       ├── target-genes-result.ts
│       ├── enrichment-result.ts
│       └── diff-result.ts
│
Sinatra App
├── views/ (ERB templates)
│   ├── layout.erb             — Shared HTML shell (head, navbar, footer)
│   ├── _navbar.erb            — Navigation partial
│   ├── _footer.erb            — Footer partial
│   └── [page].erb             — Per-page skeleton (minimal HTML, JS does the rest)
├── /api/* routes → JSON
└── /* routes → HTML via ERB
```

### Key Principles

- **Thin ERB templates** — layout shell + page skeleton only. No logic in templates.
- **TypeScript does all interactivity** — API calls, DOM updates, form handling.
- **One JS entry point per page** — esbuild produces separate bundles. Each page loads only what it needs.
- **4 shared components** — reused across pages instead of duplicated jQuery code.
- **Progressive enhancement** — pages render a meaningful skeleton without JS. JS adds interactivity.

---

## Dependencies

### Added (self-hosted, no CDN)

| File | Size (gzip) | Purpose |
|------|-------------|---------|
| `bootstrap.min.css` | ~25KB | Grid, components, utilities |
| `bootstrap.bundle.min.js` | ~20KB | Dropdowns, tabs, modals, collapse |
| `bootstrap-icons.svg` | ~60KB | SVG sprite for ~30 icons used in the app |
| `style.css` | ~3KB | App-specific overrides (colors, spacing) |
| `[page].js` (compiled TS) | ~5-15KB each | Per-page interactivity |

### Removed

| File | Size | Replaced by |
|------|------|-------------|
| `jquery.min.js` | 95KB | Native DOM API + `fetch()` |
| `bootstrap.min.js` (v3) | 35KB | Bootstrap 5 bundle |
| `bootstrap.min.css` (v3) | 109KB | Bootstrap 5 CSS |
| `typeahead.bundle.js` | 96KB | `components/autocomplete.ts` (~80 lines) |
| `jquery.flexselect.js` | 11KB | Same autocomplete component |
| `liquidmetal.js` | 4KB | Simple substring match in autocomplete |
| `fontawesome.css` + webfonts | ~250KB | Bootstrap Icons SVG sprite |
| `ExperimentList.json` | 44MB | `/api/search` with server-side pagination |
| `ExperimentList_adv.json` | 162MB | Same — search API handles both simple and detailed |
| DataTables (CDN) | ~80KB | Plain HTML table + TypeScript |
| 10 files in `pj/*.js` | ~93KB | 9 TypeScript page controllers |

**Net result:** ~700KB of JS/CSS + 206MB of JSON → ~130KB of JS/CSS + zero preloaded JSON.

---

## Shared Components

### 1. GenomeTabs (~40 lines TS)

Renders Bootstrap 5 `nav-tabs` for each genome. Emits a `genome-change` custom event. Persists selection in URL hash.

**Used on:** Peak Browser, Enrichment Analysis, Diff Analysis, Target Genes, Colo

**Interface:**
```typescript
GenomeTabs.init(container: HTMLElement, genomes: Record<string, string>)
// Listens for: container.addEventListener('genome-change', (e) => e.detail.genome)
```

### 2. FacetFilter (~120 lines TS)

Cascading dropdowns: genome → track_class → cell_type_class → qval. Each selection triggers an API call that populates the next dropdown with counts.

**Used on:** Peak Browser, Enrichment Analysis, Diff Analysis

**API calls:** `/api/track_classes`, `/api/cell_type_classes`, `/api/track_subclasses`, `/api/cell_type_subclasses`, `/api/qval_range`

**Interface:**
```typescript
FacetFilter.init(container: HTMLElement, genome: string)
FacetFilter.getCondition() → { genome, track_class, track_subclass, cell_type_class, cell_type_subclass, qval }
```

### 3. Autocomplete (~80 lines TS)

Text input with dropdown suggestions. Filters items as user types. Keyboard navigation (arrow keys, enter, escape). Uses Bootstrap 5 dropdown markup.

**Used on:** Peak Browser, Target Genes, Colo, Enrichment Analysis

**Interface:**
```typescript
Autocomplete.init(input: HTMLInputElement, items: string[], onSelect: (value: string) => void)
Autocomplete.setItems(items: string[])  // update when upstream dropdown changes
```

### 4. JobTracker (~60 lines TS)

Polls `/jobs/:id/status` every 10 seconds. Shows live clock, status badge, estimated time. Enables download links when job finishes. Fetches execution log on demand.

**Used on:** Enrichment Analysis Result, Diff Analysis Result

**Interface:**
```typescript
JobTracker.init(container: HTMLElement, jobId: string, backend: string)
```

---

## Page Inventory

### Build Order (simplest → most complex)

| Tier | Page | Components | TS Lines (est.) | Notes |
|------|------|------------|-----------------|-------|
| 0 | Layout (navbar + footer) | — | — | Shared ERB shell, all pages inherit |
| 1 | Publications, Agents, Demo, 404 | — | 0 | Static markdown rendered by kramdown |
| 2 | Homepage | — | ~20 | Fetch `/api/stats` for experiment count, 6 feature cards |
| 3 | Search | — | ~100 | Text input → `/api/search` → HTML table + pagination. Copy + TSV export. |
| 4 | Experiment Detail | — | ~150 | Metadata + 4 action dropdowns (Visualize, Analyze, Download, Link Out). IGV links. Blob downloads. |
| 5a | Target Genes (setup) | GenomeTabs, Autocomplete | ~80 | Select track + distance, submit |
| 5a | Colo (setup) | GenomeTabs, Autocomplete | ~80 | Select track + cell_type, bidirectional radio toggle |
| 5b | Target Genes Result | — | ~100 | Fetch JSON → gene × experiment score matrix. Search + sort + TSV download. |
| 5b | Colo Result | — | ~100 | Fetch JSON → partners table. Sort + TSV/GML download. |
| 6 | Enrichment Result | JobTracker | ~30 | Job polling + result links |
| 6 | Diff Analysis Result | JobTracker | ~30 | Job polling + result links |
| 7 | Peak Browser | GenomeTabs, FacetFilter, Autocomplete | ~120 | Flagship page. Cascading filters → IGV/Download buttons. |
| 8 | Enrichment Analysis | GenomeTabs, FacetFilter, Autocomplete | ~200 | Most complex. File upload, radio panels, validation, time estimation, job submission. |
| 9 | Diff Analysis | GenomeTabs, FacetFilter | ~100 | Two textareas for experiment IDs, ChIP/Bisulfite toggle, time estimation. |

**Total estimated TypeScript:** ~1,100 lines (replacing ~1,500 lines of jQuery + 206MB of JSON).

### Build Order Rationale

Start with the layout template (navbar + footer), then static pages to validate ERB + Bootstrap 5 works. Build up progressively — each tier exercises new components. Peak Browser and Enrichment Analysis come last because they use all 4 shared components, which are already tested on simpler pages by then.

---

## Page Details

### Layout (`layout.erb`)

Shared HTML shell used by all pages:
- `<head>`: meta, Bootstrap 5 CSS, `style.css`, Bootstrap Icons SVG sprite
- Navbar: logo, page links (Peak Browser, Target Genes, Colo, Enrichment Analysis, Diff Analysis, Search), experiment search input
- `<%= yield %>` for page content
- Footer: organization logos, attribution links
- Bootstrap 5 JS bundle
- Per-page JS: `<script src="/js/[page].js"></script>` (only if the page needs it)

### Static Pages (Publications, Agents, Demo, 404)

ERB template renders markdown content via `kramdown`. No TypeScript needed.

### Homepage

6 feature cards (Bootstrap 5 cards replacing Bootstrap 3 jumbotrons) linking to each tool. Experiment count fetched from `/api/stats` and displayed.

### Search

Replaces DataTables + 200MB JSON with:
- Text input + optional genome filter dropdown
- Calls `/api/search?q=...&genome=...&limit=20&offset=0`
- Renders results as HTML table with clickable experiment IDs
- Pagination (next/prev) using offset
- Copy button (Clipboard API) + TSV export (Blob download)

### Experiment Detail (`/view`)

Server-side: validates ID, fetches SRA metadata, passes to template.
Client-side TypeScript builds 4 Bootstrap 5 dropdown menus:
- **Visualize**: IGV protocol links for BigWig/BED files
- **Analyze**: Links to Colo/Target Genes for this experiment's track
- **Download**: Blob-based file downloads with loading spinners
- **Link Out**: NCBI, ENA, DDBJ, WikiGenes, PDBj, ATCC, etc.

### Target Genes (setup + result)

**Setup page:** GenomeTabs + Autocomplete for track selection. Radio buttons for distance (1kb/5kb/10kb). Submit → navigate to result page.

**Result page:** Fetches `/api/target_genes?genome=X&track=X&distance=X`. Renders a gene × experiment score matrix as a table. Gene symbol search. Column sort. TSV download via `/api/target_genes/download?format=tsv`.

### Colocalization (setup + result)

**Setup page:** GenomeTabs + Autocomplete. Radio toggle for search direction (track → cell_type OR cell_type → track). Submit → navigate to result page.

**Result page:** Fetches `/api/colo?genome=X&track=X&cell_type=X`. Renders partners table sorted by score. Columns: Rank, Track, Cell Type, Score, Shared Bins, Experiment ID (linked to /view). Downloads: TSV and GML via `/api/colo/download?format=tsv|gml`.

### Enrichment/Diff Analysis Result

Both use the JobTracker component:
- Display job ID, backend (WABI/WES), submission time
- Poll `/jobs/:id/status` every 10 seconds
- Show live clock + estimated completion time
- When finished: enable result download links (HTML + TSV)
- Log viewer: fetch `/jobs/:id/log` on demand

### Peak Browser

The flagship page. Uses all 3 UI components: GenomeTabs + FacetFilter + Autocomplete.
- Genome tabs at top
- FacetFilter populates track_class, cell_type_class dropdowns with counts
- Autocomplete for track_subclass and cell_type_subclass
- "View on IGV" button: POST to `/api/igv_url` → opens IGV protocol link
- "Download BED" button: POST to `/api/download_url` → triggers file download

### Enrichment Analysis

Most complex page. GenomeTabs + FacetFilter + Autocomplete + custom logic:
- 6 panels: experiment type → cell type → threshold → Dataset A → Dataset B → descriptions
- Dataset A: radio toggle (BED / Gene list / Count table) → textarea + file upload
- Dataset B: radio toggle (Random / BED / RefSeq / Gene list) → textarea + file upload
- "Try with example" links load example data via fetch
- Real-time validation + time estimation on textarea input
- File upload via FileReader API → content to textarea
- Submit: POST to `/jobs/submit` → redirect to result page

### Diff Analysis

GenomeTabs + FacetFilter + custom logic:
- Radio toggle: ChIP/ATAC/DNase-seq OR Bisulfite-seq
- Two textareas for experiment IDs (Dataset A + Dataset B)
- Example data loading
- Time estimation (logarithmic/linear regression)
- Submit → redirect to result page

---

## File Structure

```
frontend/                          # TypeScript source (compiled by esbuild)
├── tsconfig.json
├── api/
│   └── client.ts                  # Typed fetch wrappers for all /api/* endpoints
├── components/
│   ├── genome-tabs.ts
│   ├── facet-filter.ts
│   ├── autocomplete.ts
│   └── job-tracker.ts
└── pages/
    ├── homepage.ts
    ├── search.ts
    ├── experiment.ts
    ├── peak-browser.ts
    ├── enrichment-analysis.ts
    ├── diff-analysis.ts
    ├── target-genes.ts
    ├── colo.ts
    ├── target-genes-result.ts
    ├── colo-result.ts
    ├── enrichment-result.ts
    └── diff-result.ts

views/                             # ERB templates
├── layout.erb                     # Shared shell (head, navbar, footer)
├── _navbar.erb                    # Navigation partial
├── _footer.erb                    # Footer partial
├── about.erb                      # Homepage
├── peak_browser.erb
├── search.erb
├── experiment.erb
├── target_genes.erb
├── target_genes_result.erb
├── colo.erb
├── colo_result.erb
├── enrichment_analysis.erb
├── enrichment_analysis_result.erb
├── diff_analysis.erb
├── diff_analysis_result.erb
├── publications.erb
├── agents.erb
├── demo.erb
└── not_found.erb

public/                            # Static assets (served directly)
├── css/
│   ├── bootstrap.min.css          # Bootstrap 5 (vendored)
│   └── style.css                  # App-specific overrides
├── js/
│   ├── bootstrap.bundle.min.js    # Bootstrap 5 JS (vendored)
│   ├── homepage.js                # Compiled TS (esbuild output)
│   ├── search.js
│   ├── experiment.js
│   ├── peak-browser.js
│   ├── enrichment-analysis.js
│   ├── diff-analysis.js
│   ├── target-genes.js
│   ├── colo.js
│   ├── target-genes-result.js
│   ├── colo-result.js
│   ├── enrichment-result.js
│   └── diff-result.js
├── icons/
│   └── bootstrap-icons.svg        # SVG sprite
└── images/
    └── ...                        # Existing logos etc.

esbuild.config.mjs                 # Build config
```

---

## esbuild Configuration

```javascript
// esbuild.config.mjs
import * as esbuild from 'esbuild'

const pages = [
  'homepage', 'search', 'experiment', 'peak-browser',
  'enrichment-analysis', 'diff-analysis', 'target-genes', 'colo',
  'target-genes-result', 'colo-result', 'enrichment-result', 'diff-result',
]

await esbuild.build({
  entryPoints: pages.map(p => `frontend/pages/${p}.ts`),
  bundle: true,
  outdir: 'public/js',
  format: 'esm',
  target: ['es2020'],
  minify: process.env.NODE_ENV === 'production',
  sourcemap: process.env.NODE_ENV !== 'production',
})
```

Each page gets its own bundle. Shared components are tree-shaken — only included if the page imports them.

**Dev workflow:** `node esbuild.config.mjs --watch` for auto-rebuild on save.

---

## CSS Strategy

### style.css — App-Specific Overrides

A thin CSS file (~100 lines) that customizes Bootstrap 5 to match the current ChIP-Atlas appearance:

```css
:root {
  --bs-primary: #337ab7;       /* Keep the familiar blue */
  --bs-font-sans-serif: system-ui, -apple-system, sans-serif;
}

/* Feature cards (homepage) */
.feature-card { ... }

/* Analysis panels */
.analysis-panel { ... }

/* Experiment detail action buttons */
.action-dropdown { ... }
```

The goal is **minimal overrides** — Bootstrap 5's defaults are close to Bootstrap 3's look. Most differences are handled by updating class names (e.g., `panel` → `card`, `btn-default` → `btn-outline-secondary`).

---

## Bootstrap 3 → 5 Class Migration

Key class name changes the ERB templates need to account for:

| Bootstrap 3 | Bootstrap 5 |
|-------------|-------------|
| `panel` | `card` |
| `panel-heading` | `card-header` |
| `panel-body` | `card-body` |
| `btn-default` | `btn-outline-secondary` |
| `navbar-inverse` | `navbar-dark bg-dark` |
| `navbar-fixed-top` | `fixed-top` |
| `col-xs-*` | `col-*` |
| `img-responsive` | `img-fluid` |
| `pull-right` | `float-end` |
| `hidden-xs` | `d-none d-sm-block` |
| `form-group` | `mb-3` |
| `input-group-addon` | `input-group-text` |

---

## Result JSON Formats

Colocalization and target genes results use new JSON formats served by the backend API. Full specification in `docs/result-json-spec.md`.

---

## Testing Strategy

- **Backend API tests** — already passing (50 tests, 129 assertions)
- **Manual testing** — each page tested against the current production site for visual parity
- **Smoke test** — `script/smoke_test.sh` hits all page routes and API endpoints
- **Cross-browser** — Chrome, Firefox, Safari (desktop + mobile)
- **Accessibility** — keyboard navigation through all forms, Bootstrap 5 ARIA roles verified

---

## What Does NOT Change

- URL paths for all pages (bookmarks and scripts won't break)
- API endpoints and response formats
- Visual appearance (colors, layout, spacing)
- User workflows (same steps, same order)
- OpenAPI spec and llms.txt
- MCP server (already TypeScript, separate from this work)
