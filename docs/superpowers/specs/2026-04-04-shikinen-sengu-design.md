# ChIP-Atlas Shikinen-Sengu Plan

> *Shikinen-sengu (式年遷宮): the practice of periodically rebuilding a shrine
> with fresh materials while preserving its original form, spirit, and purpose.
> The shrine at Ise has been rebuilt every 20 years for over a millennium.*

**Date:** 2026-04-03 (updated 2026-04-04)
**Author:** Tazro Ohta + Claude
**Status:** Decisions finalized, ready to build

---

## 0. Decisions (Finalized 2026-04-04)

| # | Question | Decision |
|---|----------|----------|
| 1 | Sequel vs ActiveRecord | **Sequel** - lighter, better SQLite fit, no Rails baggage |
| 2 | SPA vs Server-rendered | **Server-rendered HTML + TypeScript** - Ruby for templates, TS for interactivity |
| 3 | DataTables / big JSON | **Drop both** - server-side paginated search via SQLite FTS5, no more 44MB JSON in browser |
| 4 | SRA metadata caching | **Yes** - cache in SQLite, source-agnostic (NCBI/EBI/SPARQL), 30-day TTL |
| 5 | Column naming | **snake_case internally, camelCase in API responses** - clean up all legacy names |
| 6 | Branch / deploy strategy | **New branch (`sengu`)** in same repo, deploy to **new AWS instance** all at once |
| 7 | Scope changes | **Add** CUT&Tag, CUT&RUN, Arabidopsis. **Drop** hg19, mm9, dm3, ce10. **Postpone** KD/KO/disease filtering (depends on bsllmner-mk2). **No chatbot** - invest in agent-friendliness instead |

### Genome assemblies (new)

```
KEEP:   hg38, mm10, rn6, dm6, ce11, sacCer3
ADD:    Arabidopsis (TAIR10)
DROP:   hg19, mm9, dm3, ce10
```

### Experiment types (new)

```
KEEP:   Histone, TFs and others, RNA polymerase, Input control,
        ATAC-Seq, DNase-seq, Bisulfite-Seq
ADD:    CUT&Tag, CUT&RUN
```

---

## 1. What We Are Preserving

ChIP-Atlas has served the epigenomics community for over a decade. Three NAR/EMBO
publications (2018, 2022, 2024). Over 1,000,000 experiments indexed. Six analysis
tools used daily by researchers worldwide. The original codename "Peak John" still
sits as a smiley face on line 1 of `app.rb`.

**What made the original design last:**
- Single-process architecture (Sinatra + SQLite) - no external services to fail
- Static metadata loaded at startup - fast, no runtime dependencies on remote DBs
- Pre-computed analysis results hosted on a separate data backend (chip-atlas.dbcls.jp)
- Heavy computation offloaded to NIG supercomputer via WABI API
- Clean separation: the app is a *window* into the data, not the data itself

**What must survive the rebuild:**
- Every API endpoint (agents and scripts depend on them)
- The OpenAPI spec contract
- The MCP server (already TypeScript, already clean)
- All 6 user workflows (Peak Browser, Enrichment, Diff, Target Genes, Colo, Search)
- The metadata Rake pipeline
- The two-tier architecture (app server + data backend)
- GSM-to-SRX redirect behavior
- WABI API integration for remote job submission
- The `llms.txt` and agent-facing documentation
- CC BY 4.0 licensing

---

## 2. What We Are Renewing

### 2.1 Frontend (the biggest change)

**Current state:**
- HAML templates (server-rendered, 24 files)
- jQuery 1.x for DOM manipulation and AJAX
- Bootstrap 3 for layout and components
- Typeahead.js + Bloodhound for autocomplete
- Flexselect for enhanced dropdowns
- Custom JS in `public/js/pj/` (~10 files, ~1500 lines total)
- IE10 viewport bug workaround (!)

**Problems:**
- jQuery and Bootstrap 3 are EOL, no security patches
- HAML ties view logic to the Ruby process
- No type safety in client-side code
- Heavy third-party JS for simple interactions
- Bootstrap 3 grid doesn't handle modern responsive needs well
- No component reuse across pages (each page reinvents filter panels)

**Renewal:**
- TypeScript for all client-side code (compiled by esbuild)
- Modern CSS (Grid, Flexbox, custom properties) - no CSS framework
- Native `<datalist>` + custom autocomplete (replaces Typeahead/Flexselect)
- `fetch()` API (replaces jQuery.ajax)
- Server-rendered HTML from ERB templates (replaces HAML)
- Progressive enhancement: pages work without JS, JS adds interactivity

### 2.2 Backend (refinement, not revolution)

**Current state:**
- Sinatra + ActiveRecord + SQLite - exactly what we want
- 506-line `app.rb` doing routing, request parsing, and response formatting
- 9 model classes in `lib/pj/` (~1,098 lines)
- Data cached in Sinatra `settings` at boot
- 18 gem dependencies

**Problems:**
- `app.rb` mixes routing with business logic
- ActiveRecord is heavy for what we need (simple queries on a read-only SQLite DB)
- Some queries load all records into Ruby memory (`self.all.map{...}.uniq`)
- FTS5 search bypasses ActiveRecord anyway (raw SQL)
- `Kernel#open` / `URI.open` used for HTTP (security concern, deprecated patterns)
- Request body parsing is manual and inconsistent
- `net-ping` gem just for a simple HTTP check
- NCBI SRA fetch happens synchronously on page load (blocks rendering)

**Renewal:**
- Keep Sinatra as the HTTP framework
- Replace ActiveRecord with Sequel (lighter, better SQLite support, still has migrations)
- Organize routes into separate files by feature
- Move business logic into service objects
- Use `Net::HTTP` or `httpx` gem consistently for all HTTP calls
- Reduce gem count from 18 to ~12

### 2.3 Database (clean schema, same engine)

**Current state:**
- SQLite with 5 AR-managed tables + 1 FTS5 virtual table
- Schema designed in 2015, largely unchanged
- camelCase column names (agClass, clSubClass) - Java naming in Ruby
- `experiments` table has no genome index
- `number_of_experiments` counts by loading ALL records into Ruby

**Renewal:**
- Keep SQLite (the right choice then, the right choice now)
- Clean schema with snake_case columns (ag_class, cl_sub_class)
- Add composite indexes for common query patterns
- Use SQL COUNT/GROUP BY instead of Ruby-side aggregation
- Keep FTS5 for full-text search
- Add a `genome` index on experiments
- Consider WAL mode for better concurrent read performance

### 2.4 Templates (HAML to ERB)

**Why ERB over HAML:**
- ERB is Ruby stdlib - zero dependencies, zero risk of abandonment
- More developers can read and modify it
- Better tooling support (IDE highlighting, linting)
- HAML's indentation-sensitivity causes subtle bugs

### 2.5 Stylesheets (SASS to plain CSS)

**Why plain CSS:**
- CSS custom properties replace SASS variables
- CSS nesting is now native (supported in all modern browsers)
- `@layer` for cascade control
- No build step needed for CSS
- One fewer gem (sass-embedded)

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Browser                          │
│  ┌───────────────────────────────────────────────┐  │
│  │  TypeScript App (esbuild-compiled)            │  │
│  │  - Page controllers (per-page logic)          │  │
│  │  - API client (typed fetch wrappers)          │  │
│  │  - UI components (autocomplete, tabs, forms)  │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │ fetch() JSON                   │
└─────────────────────┼───────────────────────────────┘
                      │
┌─────────────────────┼───────────────────────────────┐
│  Sinatra App        │                               │
│  ┌──────────────────▼────────────────────────────┐  │
│  │  Routes (organized by feature)                │  │
│  │  /api/v1/*  → JSON API (agents, frontend)     │  │
│  │  /*         → HTML pages (ERB templates)      │  │
│  └──────────────────┬────────────────────────────┘  │
│  ┌──────────────────▼────────────────────────────┐  │
│  │  Services                                     │  │
│  │  - ExperimentService (queries, faceted search)│  │
│  │  - LocationService (URL generation)           │  │
│  │  - WabiService (DDBJ job submission)          │  │
│  │  - SraService (NCBI metadata fetch)           │  │
│  └──────────────────┬────────────────────────────┘  │
│  ┌──────────────────▼────────────────────────────┐  │
│  │  Models (Sequel)                              │  │
│  │  - Experiment, Bedfile, Bedsize               │  │
│  │  - Analysis, Run                              │  │
│  │  - ExperimentSearch (FTS5)                    │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │                               │
│  ┌──────────────────▼────────────────────────────┐  │
│  │  SQLite (database.sqlite)                     │  │
│  │  WAL mode, FTS5, read-optimized               │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
          │                           │
          │ HTTP                      │ HTTP
          ▼                           ▼
  ┌───────────────┐          ┌────────────────┐
  │ chip-atlas.    │          │ dtn1.ddbj.     │
  │ dbcls.jp      │          │ nig.ac.jp      │
  │ (data backend)│          │ (WABI API)     │
  └───────────────┘          └────────────────┘
```

### 3.1 API Versioning Strategy

Introduce `/api/v1/` prefix for all JSON endpoints. Keep the old paths as aliases
for backward compatibility during transition:

```
GET /api/v1/genomes              ← new canonical path
GET /data/list_of_genome.json    ← alias (deprecated, keep forever for agents)
```

This lets us evolve the API without breaking existing integrations.

### 3.2 File Structure

```
chip-atlas/
├── app.rb                    # Entry point: require routes, configure app
├── config.ru                 # Rack entry point
├── Gemfile                   # Ruby dependencies
├── Rakefile                  # Metadata loading, DB tasks
├── database.sqlite           # SQLite database
│
├── config/
│   ├── database.yml          # DB config
│   └── nginx/                # NGINX config
│
├── db/
│   ├── migrations/           # Sequel migrations
│   └── schema.sql            # Reference schema
│
├── lib/
│   ├── models/               # Sequel model classes
│   │   ├── experiment.rb
│   │   ├── bedfile.rb
│   │   ├── bedsize.rb
│   │   ├── analysis.rb
│   │   ├── run.rb
│   │   └── experiment_search.rb
│   ├── services/             # Business logic
│   │   ├── location_service.rb
│   │   ├── wabi_service.rb
│   │   └── sra_service.rb
│   └── tasks/                # Rake tasks
│       └── metadata.rake
│
├── routes/                   # Sinatra route modules
│   ├── api.rb                # JSON API endpoints
│   ├── pages.rb              # HTML page routes
│   ├── wabi.rb               # WABI proxy routes
│   └── health.rb             # Health check
│
├── views/                    # ERB templates
│   ├── layout.erb            # Main layout
│   ├── _navigation.erb       # Shared nav
│   ├── _footer.erb           # Shared footer
│   ├── about.erb
│   ├── peak_browser.erb
│   ├── experiment.erb
│   ├── enrichment_analysis.erb
│   ├── diff_analysis.erb
│   ├── target_genes.erb
│   ├── colo.erb
│   ├── search.erb
│   ├── publications.erb
│   └── ...
│
├── frontend/                 # TypeScript source
│   ├── tsconfig.json
│   ├── api/                  # Typed API client
│   │   └── client.ts         # fetch wrappers for all endpoints
│   ├── components/           # Reusable UI components
│   │   ├── autocomplete.ts   # Typeahead replacement
│   │   ├── genome-tabs.ts    # Genome tab switcher
│   │   ├── facet-filter.ts   # Cascading filter panel
│   │   └── job-tracker.ts    # WABI job status polling
│   └── pages/                # Per-page controllers
│       ├── peak-browser.ts
│       ├── enrichment-analysis.ts
│       ├── diff-analysis.ts
│       ├── target-genes.ts
│       ├── colo.ts
│       ├── experiment.ts
│       └── search.ts
│
├── public/                   # Static assets (served directly)
│   ├── js/                   # esbuild output (compiled TS)
│   ├── css/
│   │   └── style.css         # Single CSS file, no preprocessor
│   ├── images/
│   ├── examples/
│   ├── openapi.yaml
│   ├── llms.txt
│   └── robots.txt
│
├── mcp/                      # MCP server (keep as-is)
│   ├── src/
│   └── package.json
│
├── test/                     # Tests
│   ├── test_helper.rb
│   ├── routes/
│   ├── models/
│   └── services/
│
├── script/                   # Ops scripts (keep existing)
├── Dockerfile
├── docker-compose.yml
└── esbuild.config.mjs        # TypeScript build config
```

---

## 4. Technology Decisions

### 4.1 Gems (target: ~12)

| Gem | Purpose | Replaces |
|-----|---------|----------|
| `sinatra` | Web framework | (same) |
| `rackup` | Rack runner | (same) |
| `rack-protection` | Security middleware | (same) |
| `sequel` | Database ORM | `activerecord`, `sinatra-activerecord` |
| `sqlite3` | SQLite adapter | (same) |
| `erubi` | ERB template engine | `haml` |
| `redcarpet` | Markdown rendering | (same) |
| `nokogiri` | XML parsing (SRA) | (same) |
| `unicorn` | Production server | (same) |
| `rake` | Task runner | (same) |
| `minitest` | Testing | (new) |
| `rack-test` | HTTP testing | (new) |

**Removed gems:**
- `haml` → replaced by ERB (stdlib + erubi)
- `sass-embedded` → replaced by plain CSS
- `activerecord` → replaced by Sequel
- `sinatra-activerecord` → no longer needed
- `webrick` → only needed for development, optional
- `rubyzip` → evaluate if still needed
- `net-ping` → replaced by simple `Net::HTTP` check

### 4.2 Frontend Dependencies

| Tool | Purpose | Replaces |
|------|---------|----------|
| `esbuild` | TS compilation + bundling | None (no build before) |
| `typescript` | Type checking | None |

**Removed JS libraries:**
- `jquery.min.js` → native DOM API + `fetch()`
- `bootstrap.min.js` → custom CSS + native `<details>`, `<dialog>`
- `bootstrap.min.css` → custom CSS with Grid/Flexbox
- `typeahead.bundle.js` → custom autocomplete component
- `jquery.flexselect.js` → native `<datalist>` + custom component
- `liquidmetal.js` → simple fuzzy match in TS
- `ie10-viewport-bug-workaround.js` → (IE10 is long dead)
- `fontawesome/*` → inline SVG icons or a small icon set
- `DataTables` → replaced by server-side paginated search + simple HTML table

**CDN dependencies: none.** Zero external CDN dependencies in the new app.

### 4.3 CSS Strategy

A single `style.css` file using modern CSS features:

```css
/* Custom properties for theming */
:root {
  --color-primary: #337ab7;     /* Keep the familiar blue */
  --color-bg: #fff;
  --color-text: #333;
  --spacing-unit: 0.5rem;
  --max-width: 1200px;
}

/* CSS Grid for page layouts */
.page-layout {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: var(--spacing-unit);
}

/* CSS nesting for component styles */
.filter-panel {
  & .filter-group { ... }
  & .filter-label { ... }
}
```

Design principles:
- Keep the visual identity (colors, spacing, overall feel)
- Improve mobile experience (the current site is functional but cramped on phones)
- Use system fonts (no web font downloads)
- Accessible by default (proper focus states, ARIA, contrast ratios)

---

## 5. Phase Plan

### Phase 0: Preparation (1-2 days)
- [ ] Set up the development branch (`sengu`)
- [ ] Set up esbuild with TypeScript compilation
- [ ] Create the `frontend/` directory structure
- [ ] Write the typed API client (`frontend/api/client.ts`)
- [ ] Write `style.css` with the base design system
- [ ] Set up Sequel with the existing SQLite database
- [ ] Write migration to create clean schema (snake_case columns)
- [ ] Add test infrastructure (minitest + rack-test)
- [ ] Write smoke tests that cover all existing endpoints

### Phase 1: Backend Rebuild (3-5 days)
- [ ] Port models from ActiveRecord to Sequel
  - [ ] Experiment model (the largest, ~255 lines)
  - [ ] Bedfile model
  - [ ] Bedsize model
  - [ ] Analysis model
  - [ ] Run model
  - [ ] ExperimentSearch (FTS5)
- [ ] Port services
  - [ ] LocationService (URL generation)
  - [ ] WabiService (DDBJ job submission/polling)
  - [ ] SraService (NCBI metadata - consider async/caching)
- [ ] Port routes (organized by feature)
  - [ ] API routes (JSON endpoints)
  - [ ] Page routes (HTML rendering)
  - [ ] WABI proxy routes
  - [ ] Health check
- [ ] Port metadata Rake tasks
- [ ] Port configure block (startup data loading)
- [ ] Run smoke tests against both old and new apps

### Phase 2: Frontend - Shared Components (3-5 days)
- [ ] Autocomplete component (replaces Typeahead + Flexselect)
- [ ] Genome tab switcher component
- [ ] Cascading facet filter component (the core UI pattern)
- [ ] Job tracker component (WABI status polling)
- [ ] File upload handler
- [ ] Layout template (ERB) with navigation and footer

### Phase 3: Frontend - Page by Page (5-8 days)
Port each page, keeping the same structure and workflow:
- [ ] Homepage (about) - simplest, good starting point
- [ ] Peak Browser - most complex filter UI, the flagship feature
- [ ] Experiment View - metadata display + IGV integration
- [ ] Search - DataTables integration
- [ ] Target Genes - simpler filter + typeahead
- [ ] Colocalization - similar to Target Genes
- [ ] Enrichment Analysis - complex form with file upload
- [ ] Enrichment Analysis Result - job tracking
- [ ] Diff Analysis - form with examples
- [ ] Diff Analysis Result - job tracking
- [ ] Publications - markdown rendering
- [ ] Agents/Demo - markdown rendering

### Phase 4: Polish and Verify (2-3 days)
- [ ] Cross-browser testing (Chrome, Firefox, Safari, mobile)
- [ ] Accessibility audit (keyboard navigation, screen reader)
- [ ] Performance comparison (old vs new, page load, API response)
- [ ] API compatibility verification (run MCP server against new backend)
- [ ] Update OpenAPI spec if any paths changed
- [ ] Update llms.txt
- [ ] Update smoke tests
- [ ] Docker build verification

### Phase 5: Migration (1-2 days)
- [ ] Deploy new version alongside old (blue-green or A/B)
- [ ] Monitor error logs
- [ ] Switch DNS
- [ ] Keep old version available as fallback for 1 month
- [ ] Archive old codebase as a git tag (`v1-final`)

**Estimated total: 15-25 working days**

---

## 6. Design Decisions (Confirmed)

### 6.1 Sequel (confirmed)

Sequel replaces ActiveRecord. Lighter, better SQLite/FTS5 support, no Rails
baggage. The query grammar is nearly identical; migration is mechanical.

### 6.2 Server-Rendered HTML + TypeScript (confirmed)

Sinatra renders ERB templates. TypeScript handles interactivity (filters,
autocomplete, job polling). Page navigation is regular `<a href>` links.
No SPA framework, no client-side routing.

### 6.3 Server-Side Paginated Search (confirmed)

Drop DataTables and the big JSON dump (ExperimentList.json in browser).
Replace with server-side search via SQLite FTS5 + pagination. The search
page sends queries to the API and renders results from small JSON responses.
No CDN dependencies.

### 6.4 CSS Framework: None (confirmed)

Modern CSS (Grid, Flexbox, custom properties, nesting) covers everything.
No Bootstrap. Inline SVGs replace Font Awesome.

### 6.5 SRA Metadata Caching (confirmed)

Cache experiment metadata in an `sra_cache` SQLite table. Source-agnostic:
can be populated from NCBI E-utilities, EBI API, or RDF triplestore.
30-day TTL. Eliminates synchronous NCBI calls that block page rendering.

### 6.6 Clean Naming (confirmed)

snake_case for all internal code and database columns. camelCase preserved
in API JSON responses via a serialization layer. All legacy variable names
("in silico chip" etc.) cleaned up.

### 6.7 Branch and Deploy Strategy (confirmed)

New branch `sengu` in the current repo. Build and test the complete new app.
Deploy to a new AWS instance all at once with freshly generated data.
Old instance stays running until the new one is verified.

### 6.8 Scope Changes (confirmed)

**Added to scope:**
- CUT&Tag and CUT&RUN experiment types
- Arabidopsis (TAIR10) genome assembly

**Removed from scope:**
- Old genome assemblies: hg19, mm9, dm3, ce10
- Chatbot-like search (users will use Claude/GPT with MCP instead)

**Postponed:**
- Filtering by gene KD/KO, disease, treatment (depends on bsllmner-mk2 project)

---

## 7. Migration Strategy for Data

### 7.1 Database Schema Migration

The SQLite database is loaded from flat files via Rake tasks. The migration
strategy is simple:

1. Create a new schema with clean column names
2. Update Rake tasks to load into the new schema
3. Re-run `rake metadata:load` to populate the new database
4. The old `database.sqlite` is not migrated - it's regenerated

This is safe because the database is entirely derived from the metadata files.
No user data lives in SQLite.

### 7.2 Column Name Mapping

| Old (camelCase) | New (snake_case) |
|-----------------|------------------|
| `agClass` | `ag_class` |
| `agSubClass` | `ag_sub_class` |
| `clClass` | `cl_class` |
| `clSubClass` | `cl_sub_class` |
| `clSubClassInfo` | `cl_sub_class_info` |
| `readInfo` | `read_info` |
| `additional_attributes` | `attributes` |
| `expid` | `exp_id` |

**API compatibility:** The JSON API continues to return `agClass`, `agSubClass`,
etc. The serialization layer handles the translation. Internal code uses
snake_case. External contracts don't change.

### 7.3 New Schema (Sequel Migration)

```ruby
Sequel.migration do
  change do
    create_table :experiments do
      primary_key :id
      String :exp_id, null: false, index: true
      String :genome, null: false, index: true
      String :ag_class, index: true
      String :ag_sub_class, index: true
      String :cl_class, index: true
      String :cl_sub_class, index: true
      String :cl_sub_class_info
      String :read_info
      String :title
      String :attributes
      DateTime :created_at

      index [:genome, :ag_class]
      index [:genome, :ag_class, :cl_class]
    end

    create_table :bedfiles do
      primary_key :id
      String :filename, null: false
      String :genome, null: false, index: true
      String :ag_class, index: true
      String :ag_sub_class, index: true
      String :cl_class, index: true
      String :cl_sub_class, index: true
      String :qval, index: true
      String :experiments
      DateTime :created_at

      index [:genome, :ag_class, :ag_sub_class, :cl_class, :cl_sub_class, :qval],
            name: :idx_bedfiles_lookup
    end

    create_table :bedsizes do
      primary_key :id
      String :genome, null: false
      String :ag_class
      String :cl_class
      String :qval
      Bignum :number_of_lines
      DateTime :created_at

      index [:genome, :ag_class, :cl_class, :qval], name: :idx_bedsizes_lookup
    end

    create_table :analyses do
      primary_key :id
      String :antigen, index: true
      String :cell_list
      TrueClass :target_genes, index: true
      String :genome, null: false, index: true
      DateTime :created_at
    end

    create_table :runs do
      primary_key :id
      String :run_id, null: false, index: true
      String :exp_id, null: false, index: true
      DateTime :created_at
    end

    create_table :sra_cache do
      primary_key :id
      String :exp_id, null: false, unique: true
      String :metadata_json, text: true
      DateTime :fetched_at
      DateTime :created_at
    end
  end
end
```

---

## 8. TypeScript API Client Design

The API client is the bridge between frontend and backend. Type it once,
use it everywhere:

```typescript
// frontend/api/client.ts

const BASE = '';  // Same origin

export interface ClassificationItem {
  id: string;
  label: string;
  count: number | null;
}

export interface ExperimentMetadata {
  expid: string;
  genome: string;
  agClass: string;
  agSubClass: string;
  clClass: string;
  clSubClass: string;
  title: string;
  attributes: string;
  readInfo: string;
}

export interface SearchResult {
  total: number;
  returned: number;
  experiments: ExperimentMetadata[];
}

// Classification endpoints
export async function listGenomes(): Promise<string[]> {
  return fetchJSON('/data/list_of_genome.json');
}

export async function listExperimentTypes(
  genome: string, clClass: string
): Promise<ClassificationItem[]> {
  return fetchJSON(`/data/experiment_types?genome=${enc(genome)}&clClass=${enc(clClass)}`);
}

export async function listSampleTypes(
  genome: string, agClass: string
): Promise<ClassificationItem[]> {
  return fetchJSON(`/data/sample_types?genome=${enc(genome)}&agClass=${enc(agClass)}`);
}

export async function listAntigens(
  genome: string, agClass: string, clClass?: string
): Promise<ClassificationItem[]> {
  const params = `genome=${enc(genome)}&agClass=${enc(agClass)}&clClass=${enc(clClass ?? '')}`;
  return fetchJSON(`/data/chip_antigen?${params}`);
}

export async function listCellTypes(
  genome: string, agClass: string, clClass?: string
): Promise<ClassificationItem[]> {
  const params = `genome=${enc(genome)}&agClass=${enc(agClass)}&clClass=${enc(clClass ?? '')}`;
  return fetchJSON(`/data/cell_type?${params}`);
}

// Experiment endpoints
export async function getExperiment(expid: string): Promise<ExperimentMetadata[]> {
  return fetchJSON(`/data/exp_metadata.json?expid=${enc(expid)}`);
}

export async function searchExperiments(
  query: string, genome?: string, limit?: number
): Promise<SearchResult> {
  const params = new URLSearchParams({ q: query });
  if (genome) params.set('genome', genome);
  if (limit) params.set('limit', String(limit));
  return fetchJSON(`/data/search?${params}`);
}

// Action endpoints
export async function getBrowseUrl(condition: Record<string, string>): Promise<string> {
  const res = await postJSON('/browse', { condition });
  return res.url;
}

export async function getDownloadUrl(condition: Record<string, string>): Promise<string> {
  const res = await postJSON('/download', { condition });
  return res.url;
}

// Helpers
function enc(s: string): string {
  return encodeURIComponent(s);
}

async function fetchJSON<T>(url: string): Promise<T> {
  const res = await fetch(BASE + url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

async function postJSON<T>(url: string, body: unknown): Promise<T> {
  const res = await fetch(BASE + url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}
```

---

## 9. Reusable UI Components

### 9.1 Autocomplete (replaces Typeahead + Flexselect + Bloodhound)

```typescript
// frontend/components/autocomplete.ts
// A lightweight typeahead component using <input> + <datalist> or a custom dropdown.
// Features:
// - Fuzzy matching
// - Keyboard navigation (arrow keys, enter, escape)
// - Debounced input
// - Accessible (ARIA combobox pattern)
// - Works with both static arrays and async data sources
```

### 9.2 Genome Tabs (replaces per-page tab logic)

```typescript
// frontend/components/genome-tabs.ts
// A reusable genome selector that:
// - Renders tabs for all available genomes
// - Persists selection in URL hash or sessionStorage
// - Emits a custom event when genome changes
// - All analysis pages share this exact component
```

### 9.3 Facet Filter (replaces cascading dropdown logic in peak_browser.js, etc.)

```typescript
// frontend/components/facet-filter.ts
// The core interaction pattern of ChIP-Atlas: cascading filters.
// Given a genome, the user selects:
//   experiment type → (optionally) antigen subclass
//                   → (optionally) cell type class → cell type subclass
// Each selection updates the available options and counts for downstream filters.
// This logic is currently duplicated across peak_browser.js,
// enrichment_analysis.js, and diff_analysis.js.
// Consolidate into one configurable component.
```

### 9.4 Job Tracker (replaces enrichment_analysis_result.js, diff_analysis_result.js)

```typescript
// frontend/components/job-tracker.ts
// Polls WABI API for job status. Shows:
// - Request ID
// - Submitted time
// - Estimated completion time
// - Current status (requesting → running → finished)
// - Live clock
// - Result download link when ready
// - Execution log (fetchable)
// Currently duplicated between enrichment and diff analysis result pages.
```

---

## 10. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| API contract breaks | Medium | High | Smoke tests cover all endpoints; run MCP server against new backend |
| Sequel migration issues | Low | Medium | Both ORMs talk to SQLite; schema is simple |
| Custom autocomplete UX regression | Medium | Medium | Test with real users; keep DataTables for search |
| esbuild adds build complexity | Low | Low | esbuild is <10MB, zero-config, compiles in <100ms |
| CSS regression on mobile | Medium | Medium | Test on real devices; keep layout simple |
| WABI API integration breaks | Low | High | The proxy logic is simple; test against real WABI |
| SRA cache adds stale data | Low | Low | 30-day TTL; manual cache clear via Rake task |
| Extended development time | Medium | Medium | Phase plan allows shipping incrementally |

---

## 11. What We Intentionally Keep Unchanged

- **MCP server** (`mcp/`): Already TypeScript, clean, working. Don't touch it.
- **Metadata pipeline**: Same Rake tasks, same flat file sources, same loading logic.
- **Data backend architecture**: chip-atlas.dbcls.jp serves files, app generates URLs.
- **WABI integration pattern**: POST job → poll status → redirect to results.
- **OpenAPI spec**: Same contract, maybe minor additions.
- **Deployment**: Docker + Unicorn + NGINX. Same topology.
- **The smiley face on line 1**: `:)`

---

## 12. Success Criteria

The rebuild is successful when:

1. All existing smoke tests pass against the new app
2. The MCP server works unchanged against the new backend
3. Every user workflow produces the same results as the old app
4. Page load time is equal to or better than the old app
5. The Gemfile has fewer dependencies
6. The `public/js/` directory has fewer files
7. A new developer can understand the codebase in an afternoon
8. The app runs with `bundle exec rackup` and nothing else
9. The SQLite database can be regenerated from flat files in under 5 minutes
10. It feels like the same shrine, rebuilt with fresh timber

---

## Appendix A: Current Route → New Route Mapping

| Current Path | Method | New Path | Notes |
|-------------|--------|----------|-------|
| `/` | GET | `/` | Homepage |
| `/peak_browser` | GET | `/peak_browser` | Keep |
| `/view` | GET | `/view` | Keep (with SRA caching) |
| `/colo` | GET/POST | `/colo` | Keep |
| `/target_genes` | GET/POST | `/target_genes` | Keep |
| `/enrichment_analysis` | GET/POST | `/enrichment_analysis` | Keep |
| `/enrichment_analysis_result` | GET | `/enrichment_analysis_result` | Keep |
| `/diff_analysis` | GET | `/diff_analysis` | Keep |
| `/diff_analysis_result` | GET | `/diff_analysis_result` | Keep |
| `/search` | GET | `/search` | Keep |
| `/publications` | GET | `/publications` | Keep |
| `/agents` | GET | `/agents` | Keep |
| `/demo` | GET | `/demo` | Keep |
| `/data/:data.json` | GET | `/data/:data.json` + `/api/v1/*` | Dual paths |
| `/data/experiment_types` | GET | `/data/experiment_types` | Keep |
| `/data/sample_types` | GET | `/data/sample_types` | Keep |
| `/data/chip_antigen` | GET | `/data/chip_antigen` | Keep |
| `/data/cell_type` | GET | `/data/cell_type` | Keep |
| `/data/search` | GET | `/data/search` | Keep |
| `/browse` | POST | `/browse` | Keep |
| `/download` | POST | `/download` | Keep |
| `/health` | GET | `/health` | Keep |
| `/wabi_chipatlas` | GET/POST | `/wabi_chipatlas` | Keep |
| `/wabi_endpoint_status` | GET | `/wabi_endpoint_status` | Keep |
| `/qvalue_range` | GET | `/qvalue_range` | Keep |
| `/colo_result` | GET | `/colo_result` | Keep |
| `/target_genes_result` | GET | `/target_genes_result` | Keep |
| `/enrichment_analysis_log` | GET | `/enrichment_analysis_log` | Keep |
| `/diff_analysis_log` | GET | `/diff_analysis_log` | Keep |
| `/diff_analysis_estimated_time` | POST | `/diff_analysis_estimated_time` | Keep |
| `/api/remoteUrlStatus` | GET | `/api/remoteUrlStatus` | Keep |

**Every existing path is preserved.** No breaking changes for agents or bookmarks.

---

## Appendix B: Dependency Comparison

### Ruby Gems: 18 → 12

```
REMOVED:                    ADDED:
- haml                      + sequel
- sass-embedded             + erubi
- activerecord              + minitest (dev)
- sinatra-activerecord      + rack-test (dev)
- webrick
- rubyzip (evaluate)
- net-ping

KEPT:
  sinatra, rackup, rack-protection, sqlite3,
  redcarpet, nokogiri, unicorn, rake
```

### Frontend JS: ~15 files → ~3 compiled bundles

```
REMOVED:                    ADDED:
- jquery.min.js             + app.js (compiled TS, ~50KB est.)
- bootstrap.min.js
- bootstrap.min.css
- typeahead.bundle.js
- jquery.flexselect.js
- liquidmetal.js
- ie10-viewport-bug-workaround.js
- fontawesome/* (6 CSS files + fonts)
- DataTables (CDN)
- 10 separate pj/*.js files

KEPT:
  (nothing - zero legacy JS, zero CDN dependencies)
```

---

*The shrine stands. The timber is new. The faith endures.*

---

## Appendix C: Opportunities from the Rebuild

The scientific context research (publications, GitHub issues, v4 roadmap) surfaced
items that the rebuild naturally enables. These are **not** in scope for the sengu
itself, but the new architecture makes them easier to add later:

| Opportunity | How the Rebuild Helps | Source |
|-------------|----------------------|--------|
| Partial-match typeahead | Custom autocomplete component supports fuzzy matching natively | Issue #129 (v4 roadmap) |
| CUT&Tag / CUT&RUN support | Clean data model makes adding new experiment types straightforward | Issue #129 |
| Chatbot-like search | Typed API client + MCP server already provide the foundation | Issue #129 |
| Better error feedback for Enrichment Analysis jobs | Job tracker component can show richer status (queue position, retries) | Issues #34, #55, #62, etc. |
| Field-specific search | FTS5 supports column-scoped queries; expose via API param | Issue #37 |
| SRA metadata reliability | SRA cache table eliminates synchronous NCBI calls that block pages | Issue #154 |
| Compressed downloads | Can add gzip/zip option to the download endpoint | Issue #121 |
| New organisms (Arabidopsis) | Same schema, just new genome entries in the classification | Issue #129 |
| Reproducible deployment | Docker + SQLite + flat-file regeneration = fully reproducible | Issue #129 |

**Citation impact:** ChIP-Atlas has >700 citations across 3 publications (EMBO Reports
2018, NAR 2022, NAR 2024). The rebuild preserves this by maintaining URL stability and
API backward compatibility. No researcher's script or bookmark should break.
