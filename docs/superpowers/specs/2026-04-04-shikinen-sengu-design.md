# ChIP-Atlas Shikinen-Sengu Plan

> *Shikinen-sengu (式年遷宮): the practice of periodically rebuilding a shrine
> with fresh materials while preserving its original form, spirit, and purpose.
> The shrine at Ise has been rebuilt every 20 years for over a millennium.*

**Date:** 2026-04-03 (updated 2026-05-01)
**Author:** Tazro Ohta + Claude
**Status:** Backend complete, frontend pending

---

## 0. Decisions (Finalized 2026-04-04)

| # | Question | Decision |
|---|----------|----------|
| 1 | Sequel vs ActiveRecord | **Sequel** - lighter, better SQLite fit, no Rails baggage |
| 2 | SPA vs Server-rendered | **Server-rendered HTML + TypeScript** - Ruby for templates, TS for interactivity |
| 3 | DataTables / big JSON | **Drop both** - server-side paginated search via SQLite FTS5, no more 44MB JSON in browser |
| 4 | SRA metadata caching | **Yes** - cache in SQLite, source-agnostic (NCBI/EBI/SPARQL), 30-day TTL |
| 5 | Column naming | **snake_case everywhere** - internal code, database columns, and API responses. No camelCase conversion layer. |
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

**Current state (after renewal):**
- Sinatra + Sequel + SQLite
- ~63-line `app.rb` (routing separated into route modules in `routes/`)
- 6 modules in `lib/models/` + 7 services in `lib/services/`
- Data cached in Sinatra `settings` at boot
- 7 production gems

**Problems:**
- `app.rb` mixes routing with business logic
- ActiveRecord is heavy for what we need (simple queries on a read-only SQLite DB)
- Some queries load all records into Ruby memory (`self.all.map{...}.uniq`)
- FTS5 search bypasses ActiveRecord anyway (raw SQL)
- `Kernel#open` / `URI.open` used for HTTP (security concern, deprecated patterns)
- Request body parsing is manual and inconsistent
- `net-ping` gem just for a simple HTTP check
- NCBI SRA fetch happens synchronously on page load (blocks rendering)

**Renewal (done):**
- Kept Sinatra as the HTTP framework
- Replaced ActiveRecord with Sequel (lighter, better SQLite support, still has migrations)
- Organized routes into separate files by feature (`routes/api.rb`, `routes/pages.rb`, `routes/jobs.rb`, `routes/health.rb`)
- Moved business logic into service objects (`lib/services/`)
- Using `Net::HTTP` consistently for all HTTP calls
- Reduced gem count from 18 to 7 production gems
- Switched from Unicorn to Puma

### 2.3 Database (clean schema, same engine)

**Current state:**
- SQLite with 5 AR-managed tables + 1 FTS5 virtual table
- Schema designed in 2015, largely unchanged
- camelCase column names (agClass, clSubClass) - Java naming in Ruby
- `experiments` table has no genome index
- `number_of_experiments` counts by loading ALL records into Ruby

**Renewal (done):**
- Kept SQLite (the right choice then, the right choice now)
- Clean schema with snake_case columns: `track_class`, `track_subclass`, `cell_type_class`, `cell_type_subclass` (not `ag_class`/`cl_class`); `experiment_id` (not `exp_id`); `track` in analyses (not `antigen`)
- Composite indexes implemented for common query patterns (e.g., `[:genome, :track_class, :cell_type_class]`, `idx_bedfiles_lookup`)
- SQL COUNT/GROUP BY instead of Ruby-side aggregation
- FTS5 virtual table (`experiments_fts`) for full-text search
- `genome` index on experiments
- WAL mode enabled for better concurrent read performance

### 2.4 Templates (HAML to ERB)

**Decision made, migration in progress.** New templates are written in ERB; legacy HAML templates are being converted as pages are rebuilt.

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
│  │  /api/*     → JSON API (agents, frontend)     │  │
│  │  /*         → HTML pages (ERB templates)      │  │
│  └──────────────────┬────────────────────────────┘  │
│  ┌──────────────────▼────────────────────────────┐  │
│  │  Services                                     │  │
│  │  - LocationService (URL generation)           │  │
│  │  - WabiService (DDBJ job submission)          │  │
│  │  - SraService (NCBI metadata fetch)           │  │
│  │  - SapporoService, ComputeRouter, DataProxy   │  │
│  │  - ServiceMonitor                             │  │
│  └──────────────────┬────────────────────────────┘  │
│  ┌──────────────────▼────────────────────────────┐  │
│  │  Models (Sequel)                              │  │
│  │  - Experiment, Bedfile, Bedsize               │  │
│  │  - Analysis, SraCache                         │  │
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

### 3.1 API Path Strategy

All JSON endpoints live under flat `/api/` paths with no versioning prefix:

```
GET /api/genomes
GET /api/search
GET /api/track_classes
GET /api/cell_type_classes
GET /api/track_subclasses
GET /api/cell_type_subclasses
GET /api/experiment
GET /api/stats
...
```

No `/api/v1/` prefix was introduced. No `/data/` aliases were kept. The old
`/data/list_of_genome.json`-style paths are gone; agents should use `/api/genomes` etc.

### 3.2 File Structure

```
chip-atlas/
├── app.rb                    # Entry point: require routes, configure app (~63 lines)
├── config.ru                 # Rack entry point
├── Gemfile                   # Ruby dependencies
├── Rakefile                  # Metadata loading, DB tasks
├── database.sqlite           # SQLite database
├── .dockerignore
│
├── config/
│   ├── puma.rb               # Puma server config
│   └── nginx/                # NGINX config
│
├── db/
│   ├── migrations/           # Sequel migrations
│   └── schema.sql            # Reference schema
│
├── lib/
│   ├── chip_atlas.rb         # Namespace and shared setup
│   ├── db.rb                 # Database connection
│   ├── models/               # Sequel model classes
│   │   ├── experiment.rb
│   │   ├── bedfile.rb
│   │   ├── bedsize.rb
│   │   ├── analysis.rb
│   │   ├── sra_cache.rb
│   │   └── experiment_search.rb
│   ├── services/             # Business logic
│   │   ├── location_service.rb
│   │   ├── wabi_service.rb
│   │   ├── sra_service.rb
│   │   ├── sapporo_service.rb
│   │   ├── compute_router.rb
│   │   ├── data_proxy.rb
│   │   └── service_monitor.rb
│   ├── middleware/
│   │   └── json_body_parser.rb
│   └── tasks/                # Rake tasks
│       ├── metadata.rake
│       └── clean_old_genomes.rake
│
├── routes/                   # Sinatra route modules
│   ├── api.rb                # JSON API endpoints
│   ├── pages.rb              # HTML page routes
│   ├── jobs.rb               # Job submission routes (Sapporo/WABI)
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
├── frontend/                 # TypeScript source (planned)
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
└── esbuild.config.mjs        # TypeScript build config (planned)
```

---

## 4. Technology Decisions

### 4.1 Gems (actual: 7 production, 3 dev)

**Production gems:**

| Gem | Purpose | Replaces |
|-----|---------|----------|
| `sinatra` | Web framework (includes rack, rack-protection, tilt) | (same) |
| `puma` | Production server | `unicorn` |
| `sequel` | Database ORM | `activerecord`, `sinatra-activerecord` |
| `sqlite3` | SQLite adapter | (same) |
| `kramdown` | Markdown rendering | `redcarpet` |
| `rexml` | XML parsing | `nokogiri` |
| `rake` | Task runner | (same) |

**Dev/test gems:**

| Gem | Purpose |
|-----|---------|
| `webrick` | Dev server |
| `minitest` | Testing |
| `rack-test` | HTTP testing |

**Removed gems:**
- `haml` → replaced by ERB (Ruby stdlib, no gem needed)
- `sass-embedded` → replaced by plain CSS
- `activerecord` → replaced by Sequel
- `sinatra-activerecord` → no longer needed
- `webrick` → moved to dev-only dependency
- `rubyzip` → removed
- `net-ping` → replaced by simple `Net::HTTP` check
- `nokogiri` → replaced by `rexml` (stdlib-adjacent, lighter)
- `redcarpet` → replaced by `kramdown` (pure Ruby, no C extension)
- `unicorn` → replaced by `puma`
- `rackup` → not needed (Puma includes its own Rack handler)
- `rack-protection` → included in `sinatra` gem
- `erubi` → using ERB from Ruby stdlib instead

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

### Phase 0: Preparation -- PARTIAL (backend done 2026-04-04, frontend setup pending)
- [x] Set up the development branch (`sengu`)
- [ ] Set up esbuild with TypeScript compilation
- [ ] Create the `frontend/` directory structure
- [ ] Write the typed API client (`frontend/api/client.ts`)
- [ ] Write `style.css` with the base design system
- [x] Set up Sequel with the existing SQLite database
- [x] Write migration to create clean schema (snake_case columns)
- [x] Add test infrastructure (minitest + rack-test)
- [x] Write smoke tests that cover all existing endpoints

### Phase 1: Backend Rebuild -- DONE (completed 2026-04-05, reviews through 2026-04-30)
- [x] Port models from ActiveRecord to Sequel
  - [x] Experiment model (the largest, ~255 lines)
  - [x] Bedfile model
  - [x] Bedsize model
  - [x] Analysis model
  - [x] ExperimentSearch (FTS5)
- [x] Port services
  - [x] LocationService (URL generation)
  - [x] ComputeRouter (multi-backend job routing, replaces WabiService)
  - [x] SapporoService (WES-based job submission)
  - [x] SraService (NCBI metadata with caching)
  - [x] DataProxy (proxied data fetching from chip-atlas.dbcls.jp)
  - [x] ServiceMonitor (health checks for external backends)
- [x] Port routes (organized by feature)
  - [x] API routes (`routes/api.rb` -- JSON endpoints)
  - [x] Page routes (`routes/pages.rb` -- HTML rendering)
  - [x] Job routes (`routes/jobs.rb` -- compute job submission/polling)
  - [x] Health routes (`routes/health.rb` -- health check + service status)
- [x] Port metadata Rake tasks
- [x] Port configure block (startup data loading)
- [x] Run smoke tests against both old and new apps

### Phase 2: Frontend - Shared Components (3-5 days) -- TODO
- [ ] Autocomplete component (replaces Typeahead + Flexselect)
- [ ] Genome tab switcher component
- [ ] Cascading facet filter component (the core UI pattern)
- [ ] Job tracker component (compute job status polling)
- [ ] File upload handler
- [ ] Layout template (ERB) with navigation and footer

### Phase 3: Frontend - Page by Page (5-8 days) -- TODO
Port each page, keeping the same structure and workflow:
- [ ] Homepage (about) - simplest, good starting point
- [ ] Peak Browser - most complex filter UI, the flagship feature
- [ ] Experiment View - metadata display + IGV integration
- [ ] Search - server-side paginated search via FTS5
- [ ] Target Genes - simpler filter + typeahead
- [ ] Colocalization - similar to Target Genes
- [ ] Enrichment Analysis - complex form with file upload
- [ ] Enrichment Analysis Result - job tracking
- [ ] Diff Analysis - form with examples
- [ ] Diff Analysis Result - job tracking
- [ ] Publications - markdown rendering
- [ ] Agents/Demo - markdown rendering

### Phase 4: Polish and Verify (2-3 days) -- TODO
- [ ] Cross-browser testing (Chrome, Firefox, Safari, mobile)
- [ ] Accessibility audit (keyboard navigation, screen reader)
- [ ] Performance comparison (old vs new, page load, API response)
- [ ] API compatibility verification (run MCP server against new backend)
- [ ] Update OpenAPI spec if any paths changed
- [ ] Update llms.txt
- [ ] Update smoke tests
- [ ] Docker build verification

### Phase 5: Migration (1-2 days) -- TODO
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

### 6.4 CSS Framework: Bootstrap 5 (confirmed)

Bootstrap 5, self-hosted (vendored in public/). Upgrade from current Bootstrap 3.
No CDN dependencies. Chosen for 15-year track record, built-in accessibility,
and minimal visual change from the current app. Inline SVGs replace Font Awesome.

### 6.5 SRA Metadata Caching (confirmed)

Cache experiment metadata in an `sra_cache` SQLite table. Source-agnostic:
can be populated from NCBI E-utilities, EBI API, or RDF triplestore.
30-day TTL. Eliminates synchronous NCBI calls that block page rendering.

### 6.6 Clean Naming (confirmed)

snake_case everywhere -- database columns, internal Ruby code, AND API JSON
responses. No camelCase conversion layer, no serialization step. The frontend
TypeScript and agents use snake_case field names directly (e.g.
`track_class`, `cell_type_subclass`, `experiment_id`). All legacy variable
names ("in silico chip", "agClass", etc.) cleaned up.

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

| Old | New |
|-----|-----|
| `agClass` | `track_class` |
| `agSubClass` | `track_subclass` |
| `clClass` | `cell_type_class` |
| `clSubClass` | `cell_type_subclass` |
| `clSubClassInfo` | `cell_type_subclass_info` |
| `readInfo` | `read_info` |
| `additional_attributes` | `attributes` |
| `expid` | `experiment_id` |
| `antigen` (in analyses) | `track` |

snake_case is used consistently in the database, internal code, and API
responses. There is no camelCase serialization layer.

### 7.3 New Schema (Sequel Migration)

From `db/migrations/001_create_schema.rb`:

```ruby
Sequel.migration do
  up do
    create_table :experiments do
      primary_key :id
      String :experiment_id, null: false
      String :genome, null: false
      String :track_class
      String :track_subclass
      String :cell_type_class
      String :cell_type_subclass
      String :cell_type_subclass_info
      String :read_info
      String :title
      String :attributes, text: true
      DateTime :created_at

      index :experiment_id
      index :genome
      index :track_class
      index :track_subclass
      index :cell_type_class
      index :cell_type_subclass
      index [:genome, :track_class]
      index [:genome, :track_class, :cell_type_class]
    end

    create_table :bedfiles do
      primary_key :id
      String :filename, null: false
      String :genome, null: false
      String :track_class
      String :track_subclass
      String :cell_type_class
      String :cell_type_subclass
      String :qval
      String :experiments, text: true
      DateTime :created_at

      index :genome
      index [:genome, :track_class, :track_subclass, :cell_type_class, :cell_type_subclass, :qval],
            name: :idx_bedfiles_lookup
    end

    create_table :bedsizes do
      primary_key :id
      String :genome, null: false
      String :track_class
      String :cell_type_class
      String :qval
      Bignum :number_of_lines
      DateTime :created_at

      index [:genome, :track_class, :cell_type_class, :qval], name: :idx_bedsizes_lookup
    end

    create_table :analyses do
      primary_key :id
      String :track
      String :cell_list, text: true
      TrueClass :target_genes
      String :genome, null: false
      DateTime :created_at

      index :track
      index :genome
      index :target_genes
    end

    create_table :sra_cache do
      primary_key :id
      String :experiment_id, null: false, unique: true
      String :metadata_json, text: true
      DateTime :fetched_at
      DateTime :created_at
    end

    run <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS experiments_fts USING fts5(
        experiment_id,
        sra_id,
        geo_id,
        genome,
        track_class,
        track_subclass,
        cell_type_class,
        cell_type_subclass,
        title,
        attributes
      );
    SQL
  end

  down do
    run "DROP TABLE IF EXISTS experiments_fts"
    drop_table :sra_cache
    drop_table :analyses
    drop_table :bedsizes
    drop_table :bedfiles
    drop_table :experiments
  end
end
```

---

## 8. TypeScript API Client Design

The API client is the bridge between frontend and backend. Type it once,
use it everywhere. All field names use snake_case to match the API responses
directly -- no camelCase conversion needed.

```typescript
// frontend/api/client.ts

const BASE = '';  // Same origin

export interface ClassificationItem {
  id: string;
  label: string;
  count: number | null;
}

export interface ExperimentMetadata {
  experiment_id: string;
  genome: string;
  track_class: string;
  track_subclass: string;
  cell_type_class: string;
  cell_type_subclass: string;
  cell_type_subclass_info: string;
  title: string;
  attributes: string;
  read_info: string;
}

export interface SearchResult {
  total: number;
  returned: number;
  experiments: ExperimentMetadata[];
}

export interface JobSubmission {
  backend: string;
  job_id: string;
}

export interface JobStatus {
  backend: string;
  job_id: string;
  status: string;
  retry: boolean;
}

export interface HealthCheck {
  status: string;
  checks: Record<string, string>;
}

// === Classification endpoints ===

export async function listGenomes(): Promise<Record<string, string>> {
  return fetchJSON('/api/genomes');
}

export async function getStats(): Promise<Record<string, unknown>> {
  return fetchJSON('/api/stats');
}

export async function listTrackClasses(
  genome?: string, cell_type_class?: string
): Promise<ClassificationItem[]> {
  const params = new URLSearchParams();
  if (genome) params.set('genome', genome);
  if (cell_type_class) params.set('cell_type_class', cell_type_class);
  return fetchJSON(`/api/track_classes?${params}`);
}

export async function listCellTypeClasses(
  genome: string, track_class: string
): Promise<ClassificationItem[]> {
  return fetchJSON(
    `/api/cell_type_classes?genome=${enc(genome)}&track_class=${enc(track_class)}`
  );
}

export async function listTrackSubclasses(
  genome: string, track_class: string, cell_type_class?: string
): Promise<ClassificationItem[]> {
  const params = `genome=${enc(genome)}&track_class=${enc(track_class)}`;
  const extra = cell_type_class ? `&cell_type_class=${enc(cell_type_class)}` : '';
  return fetchJSON(`/api/track_subclasses?${params}${extra}`);
}

export async function listCellTypeSubclasses(
  genome: string, track_class: string, cell_type_class?: string
): Promise<ClassificationItem[]> {
  const params = `genome=${enc(genome)}&track_class=${enc(track_class)}`;
  const extra = cell_type_class ? `&cell_type_class=${enc(cell_type_class)}` : '';
  return fetchJSON(`/api/cell_type_subclasses?${params}${extra}`);
}

// === Data endpoints ===

export async function getGenomeIndex(): Promise<Record<string, unknown>> {
  return fetchJSON('/api/genome_index');
}

export async function getExperiment(experiment_id: string): Promise<ExperimentMetadata> {
  return fetchJSON(`/api/experiment?experiment_id=${enc(experiment_id)}`);
}

export async function searchExperiments(
  query: string, genome?: string, limit?: number, offset?: number
): Promise<SearchResult> {
  const params = new URLSearchParams({ q: query });
  if (genome) params.set('genome', genome);
  if (limit) params.set('limit', String(limit));
  if (offset) params.set('offset', String(offset));
  return fetchJSON(`/api/search?${params}`);
}

export async function getQvalRange(): Promise<string[]> {
  return fetchJSON('/api/qval_range');
}

export async function getBedSizes(): Promise<Record<string, unknown>> {
  return fetchJSON('/api/bed_sizes');
}

// === Analysis index endpoints ===

export async function getColoIndex(genome: string): Promise<unknown[]> {
  return fetchJSON(`/api/colo_index?genome=${enc(genome)}`);
}

export async function getTargetGenesIndex(): Promise<unknown[]> {
  return fetchJSON('/api/target_genes_index');
}

export async function getTargetGenesDistances(): Promise<string[]> {
  return fetchJSON('/api/target_genes_distances');
}

// === URL generation endpoints ===

export async function getIgvUrl(condition: Record<string, string>): Promise<string> {
  const params = new URLSearchParams(condition);
  const res = await fetchJSON<{ url: string }>(`/api/igv_url?${params}`);
  return res.url;
}

export async function getIgvUrlPost(condition: Record<string, string>): Promise<string> {
  const res = await postJSON<{ url: string }>('/api/igv_url', { condition });
  return res.url;
}

export async function getDownloadUrl(condition: Record<string, string>): Promise<string> {
  const params = new URLSearchParams(condition);
  const res = await fetchJSON<{ url: string }>(`/api/download_url?${params}`);
  return res.url;
}

export async function getDownloadUrlPost(condition: Record<string, string>): Promise<string> {
  const res = await postJSON<{ url: string }>('/api/download_url', { condition });
  return res.url;
}

// === Data proxy endpoints ===

export async function getColoData(
  genome: string, track: string, cell_type: string
): Promise<unknown> {
  return fetchJSON(
    `/api/colo?genome=${enc(genome)}&track=${enc(track)}&cell_type=${enc(cell_type)}`
  );
}

export async function getTargetGenesData(
  genome: string, track: string, distance: string
): Promise<unknown> {
  return fetchJSON(
    `/api/target_genes?genome=${enc(genome)}&track=${enc(track)}&distance=${enc(distance)}`
  );
}

export function coloDownloadUrl(
  genome: string, track: string, cell_type: string, format: 'tsv' | 'gml'
): string {
  return `/api/colo/download?genome=${enc(genome)}&track=${enc(track)}&cell_type=${enc(cell_type)}&format=${format}`;
}

export function targetGenesDownloadUrl(
  genome: string, track: string, distance: string, format: 'tsv'
): string {
  return `/api/target_genes/download?genome=${enc(genome)}&track=${enc(track)}&distance=${enc(distance)}&format=${format}`;
}

// === Job endpoints ===

export async function getAvailableBackend(type?: string): Promise<Record<string, unknown>> {
  const params = type ? `?type=${enc(type)}` : '';
  return fetchJSON(`/jobs/available${params}`);
}

export async function submitJob(
  type: string, jobParams: Record<string, unknown>
): Promise<JobSubmission> {
  return postJSON('/jobs/submit', { type, params: jobParams });
}

export async function getJobStatus(id: string, backend: string): Promise<JobStatus> {
  return fetchJSON(`/jobs/${enc(id)}/status?backend=${enc(backend)}`);
}

export async function getJobResult(
  id: string, backend: string
): Promise<{ urls: Record<string, string> }> {
  return fetchJSON(`/jobs/${enc(id)}/result?backend=${enc(backend)}`);
}

export async function getJobLog(id: string, backend: string): Promise<string> {
  const res = await fetch(`${BASE}/jobs/${enc(id)}/log?backend=${enc(backend)}`);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.text();
}

export async function getEstimatedTime(
  analysis: string, ids: string[]
): Promise<{ minutes: number | null }> {
  return postJSON('/jobs/estimated_time', { analysis, ids });
}

// === Health endpoints ===

export async function getHealth(): Promise<HealthCheck> {
  return fetchJSON('/health');
}

export async function getStatus(): Promise<Record<string, unknown>> {
  return fetchJSON('/status');
}

// === Helpers ===

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
//   track class → (optionally) track subclass
//               → (optionally) cell type class → cell type subclass
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
- **Deployment**: Docker + Puma + NGINX. Same topology.
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
8. The app runs with `bundle exec puma -C config/puma.rb` and nothing else
9. The SQLite database can be regenerated from flat files in under 5 minutes
10. It feels like the same shrine, rebuilt with fresh timber

---

## Appendix A: Route Mapping

### Page routes (`routes/pages.rb`)

| Path | Method | Notes |
|------|--------|-------|
| `/` | GET | Homepage |
| `/peak_browser` | GET | Peak Browser |
| `/view` | GET | Experiment detail (with SRA caching, GSM redirect) |
| `/colo` | GET | Colocalization setup |
| `/colo_result` | GET | Colocalization results |
| `/target_genes` | GET | Target Genes setup |
| `/target_genes_result` | GET | Target Genes results |
| `/enrichment_analysis` | GET/POST | Enrichment Analysis form |
| `/enrichment_analysis_result` | GET | Enrichment Analysis results |
| `/diff_analysis` | GET | Diff Analysis form |
| `/diff_analysis_result` | GET | Diff Analysis results |
| `/search` | GET | Search page |
| `/publications` | GET | Publications |
| `/agents` | GET | Agent documentation |
| `/demo` | GET | Demo page |

### API routes (`routes/api.rb`)

| Path | Method | Notes |
|------|--------|-------|
| `/api/genomes` | GET | List genome assemblies (id -> label hash) |
| `/api/stats` | GET | Experiment counts per genome |
| `/api/track_classes` | GET | List track classes (optionally filtered by genome) |
| `/api/cell_type_classes` | GET | List cell type classes (requires genome + track_class) |
| `/api/track_subclasses` | GET | List track subclasses (requires genome + track_class) |
| `/api/cell_type_subclasses` | GET | List cell type subclasses (requires genome + track_class) |
| `/api/subclasses` | GET | Legacy combined subclass endpoint |
| `/api/genome_index` | GET | Cached index for all genomes |
| `/api/experiment` | GET | Single experiment metadata by experiment_id |
| `/api/search` | GET | Full-text search with pagination (q, genome, limit, offset) |
| `/api/qval_range` | GET | Available q-value thresholds |
| `/api/bed_sizes` | GET | BED file size data |
| `/api/colo_index` | GET | Colocalization index by genome |
| `/api/target_genes_index` | GET | Target genes analysis index |
| `/api/target_genes_distances` | GET | Available distance thresholds |
| `/api/igv_url` | GET/POST | Generate IGV browsing URL |
| `/api/download_url` | GET/POST | Generate archive download URL |
| `/api/colo` | GET | Colocalization data (proxied from data server) |
| `/api/colo/download` | GET | Colocalization file download (tsv/gml) |
| `/api/target_genes` | GET | Target genes data (proxied from data server) |
| `/api/target_genes/download` | GET | Target genes file download (tsv) |
| `/api/remote_url_status` | GET | Check remote URL availability (internal) |

### Job routes (`routes/jobs.rb`)

| Path | Method | Notes |
|------|--------|-------|
| `/jobs/available` | GET | Check available compute backend |
| `/jobs/submit` | POST | Submit enrichment or diff analysis job |
| `/jobs/:id/status` | GET | Poll job status (requires backend param) |
| `/jobs/:id/result` | GET | Get result URLs |
| `/jobs/:id/log` | GET | Get execution log |
| `/jobs/estimated_time` | POST | Estimate diff analysis runtime |

### Health routes (`routes/health.rb`)

| Path | Method | Notes |
|------|--------|-------|
| `/health` | GET | Internal health check (database, experiment count) |
| `/status` | GET | External service status (for frontend alerts) |

All old `/data/*` paths have been removed. The API uses `/api/*` exclusively.

---

## Appendix B: Dependency Comparison

### Ruby Gems: 18 → 10 (7 production + 3 dev)

**Production (7 gems):**
sinatra, puma, sequel, sqlite3, kramdown, rexml, rake

**Development (3 gems):**
webrick, minitest, rack-test

**Removed gems (9+):**
- `haml` -- replaced by ERB (stdlib)
- `sass-embedded` -- replaced by plain CSS
- `activerecord` -- replaced by Sequel
- `sinatra-activerecord` -- no longer needed
- `nokogiri` -- replaced by rexml (stdlib-adjacent, lighter)
- `redcarpet` -- replaced by kramdown (pure Ruby)
- `unicorn` -- replaced by Puma
- `rackup` -- bundled in Puma
- `rack-protection` -- bundled in Sinatra
- `net-ping` -- replaced by simple `Net::HTTP` check
- `rubyzip` -- no longer needed
- `erubi` -- ERB stdlib is sufficient

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

**Frontend build tooling:** esbuild + TypeScript (same plan as before)

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
