# Shared Components + Search/Experiment Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the four shared TypeScript components (GenomeTabs, Autocomplete, FacetFilter, JobTracker) and convert the Search and Experiment Detail pages from HAML to ERB+TypeScript. This is Plan 2 of 3 — it produces user-visible value (working /search and /view pages) and unblocks Plan 3 (analysis pages) by delivering all four shared components.

**Architecture:** Each shared component is a self-contained TypeScript module under `frontend/components/`. Components expose a small static API (`.init(...)`, `.getCondition()`, `.setItems(...)`) and emit DOM events for cross-component coordination. ERB templates render a minimal skeleton plus a JSON-island `<script type="application/json">` data blob; the per-page TypeScript reads the blob, fetches additional data, and wires up UI. No jQuery. No DataTables. Bootstrap 5 dropdowns/tabs are used via their data-attribute API where possible, with explicit JS only when required.

**Tech Stack:** TypeScript strict mode, esbuild, Bootstrap 5.3.3, ERB (Ruby stdlib), Sinatra, Sequel, Kramdown.

**Reference:** Frontend design spec at `docs/superpowers/specs/2026-05-12-frontend-rebuild-design.md`. API client at `frontend/api/client.ts` (built in Plan 1). Existing HAML at `views/search.haml` and `views/experiment.haml` (kept as reference, not deleted in this plan).

**Important notes:**
- Ruby is at `/opt/homebrew/opt/ruby/bin/ruby`. Prefix Ruby/bundle commands with `PATH="/opt/homebrew/opt/ruby/bin:$PATH"`.
- Tests must run with `RACK_ENV=test` to bypass the production host_authorization middleware (which only permits `.chip-atlas.org`).
- The compiled `public/js/search.js` and `public/js/experiment.js` are gitignored (per Plan 1). Do NOT stage them.
- esbuild auto-discovers `frontend/pages/*.ts` — adding a new page TS file is enough; no esbuild config edit needed.
- The `frontend/components/` directory exists empty (created by Plan 1's tsconfig setup). The `@components/*` path alias in `frontend/tsconfig.json` resolves to `frontend/components/` — but esbuild also resolves relative imports natively, so use relative imports (`../components/foo`) for consistency with Plan 1.
- HAML files (`views/search.haml`, `views/experiment.haml`, etc.) are NOT deleted in this plan. A later cleanup task will remove them once Plan 3 ships.
- The current `/view` route in `routes/pages.rb` does NOT fetch `@records` — only `@expid` and `@ncbi`. Task 3 adds the fetch.
- The `/search` route renders `erb :search` and passes no instance variables. Task 2 keeps it that way (everything is client-driven).

---

## File Structure (what this plan creates)

```
chip-atlas/
├── frontend/
│   ├── api/
│   │   └── client.ts                   # MODIFY: add SearchExperiment type
│   ├── components/
│   │   ├── genome-tabs.ts              # NEW
│   │   ├── autocomplete.ts             # NEW
│   │   ├── facet-filter.ts             # NEW
│   │   └── job-tracker.ts              # NEW
│   └── pages/
│       ├── search.ts                   # NEW
│       └── experiment.ts               # NEW
├── views/
│   ├── search.erb                      # NEW
│   └── experiment.erb                  # NEW
├── routes/
│   └── pages.rb                        # MODIFY: /view fetches @records, sets @page_js
└── public/
    └── css/
        └── style.css                   # MODIFY: append component styles
```

---

### Task 1: Update API Client — Add SearchExperiment Type

**Files:**
- Modify: `frontend/api/client.ts`
- Test: `npx tsc --project frontend/tsconfig.json --noEmit`

The `/api/search` endpoint returns records with `sra_id` and `geo_id` (from the FTS5 table) — fields that the current `ExperimentRecord` interface does not declare. The `/api/experiment` endpoint returns a different shape (with `read_info` and `cell_type_subclass_info` but without `sra_id`/`geo_id`). They should be separate types.

- [ ] **Step 1: Add `SearchExperiment` interface and update `SearchResult`**

Edit `/Users/inutano/repos/chip-atlas/frontend/api/client.ts`. Find:

```typescript
export interface ExperimentRecord {
  experiment_id: string
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  title: string
  attributes: string
  read_info: string
  cell_type_subclass_info: string
}
```

Replace with:

```typescript
export interface ExperimentRecord {
  experiment_id: string
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  title: string
  attributes: string
  read_info: string
  cell_type_subclass_info: string
}

export interface SearchExperiment {
  experiment_id: string
  sra_id: string
  geo_id: string
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  title: string
  attributes: string
}
```

Then find:

```typescript
export interface SearchResult {
  total: number
  returned: number
  experiments: ExperimentRecord[]
}
```

Replace with:

```typescript
export interface SearchResult {
  total: number
  returned: number
  experiments: SearchExperiment[]
}
```

- [ ] **Step 2: Verify TypeScript still compiles**

Run:
```bash
cd /Users/inutano/repos/chip-atlas && npx tsc --project frontend/tsconfig.json --noEmit
```

Expected: exit 0, no output.

- [ ] **Step 3: Commit**

Stage only `frontend/api/client.ts`. HEREDOC commit message:

```
Split SearchExperiment from ExperimentRecord

The /api/search and /api/experiment endpoints return different shapes:
search includes sra_id and geo_id from the FTS5 table, while
experiment returns read_info and cell_type_subclass_info from the
experiments table. Modeling them as one type would force every caller
to optional-chain on fields that are not optional in either response.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 2: Search Page

**Files:**
- Create: `views/search.erb`
- Create: `frontend/pages/search.ts`
- Modify: `public/css/style.css` (append search-page rules)
- Modify: `routes/pages.rb` (set `@page_js = 'search'` on `/search`)
- Build: `node esbuild.config.mjs`
- Test: `GET /search` returns 200; manual end-to-end via rack-test for the rendered skeleton

The current `/search` route is just `erb :search`. We keep it that way (zero server-side data), set `@page_js = 'search'` for the JS bundle, and have the TS handle query input, API call, table rendering, pagination, copy-to-clipboard, and TSV export.

- [ ] **Step 1: Update `/search` route to set `@page_js`**

Edit `/Users/inutano/repos/chip-atlas/routes/pages.rb`. Find:

```ruby
        app.get '/search' do
          erb :search
        end
```

Replace with:

```ruby
        app.get '/search' do
          @page_js = 'search'
          erb :search
        end
```

- [ ] **Step 2: Create `views/search.erb`**

Write to `/Users/inutano/repos/chip-atlas/views/search.erb`:

```erb
<%
  @page_title = 'Dataset Search'
  @page_description = 'Search ChIP-Atlas dataset by keywords.'
  @active_menu = nil
%>
<div class="row mb-3">
  <div class="col-md-10">
    <h1>ChIP-Atlas: Dataset Search</h1>
    <p>Find experiments by keywords. Same track type classes, cell type classes, and reference genomes as the
      <a href="/peak_browser">Peak Browser</a>. For bulk processing, see the
      <a href="https://github.com/inutano/chip-atlas/wiki#tables-summarizing-metadata-and-files" target="_blank" rel="noopener noreferrer">metadata table</a>.
    </p>
  </div>
</div>

<form id="search-form" class="row g-2 mb-3" role="search" autocomplete="off">
  <div class="col-md-7">
    <input type="search" id="search-query" class="form-control" placeholder="e.g. K562 H3K4me3" aria-label="Search query">
  </div>
  <div class="col-md-3">
    <select id="search-genome" class="form-select" aria-label="Filter by genome">
      <option value="">All genomes</option>
    </select>
  </div>
  <div class="col-md-2">
    <button type="submit" class="btn btn-primary w-100">Search</button>
  </div>
</form>

<div id="search-status" class="mb-2 text-muted small" aria-live="polite"></div>

<div id="search-results-wrap" class="mb-3" hidden>
  <div class="d-flex justify-content-between align-items-center mb-2">
    <div id="search-summary" class="small text-muted"></div>
    <div class="btn-group btn-group-sm" role="group">
      <button type="button" id="copy-results" class="btn btn-outline-secondary" title="Copy table to clipboard">Copy</button>
      <button type="button" id="download-tsv" class="btn btn-outline-secondary" title="Download results as TSV">TSV</button>
    </div>
  </div>
  <div class="table-responsive">
    <table class="table table-striped table-sm">
      <thead>
        <tr>
          <th scope="col">SRX</th>
          <th scope="col">SRA</th>
          <th scope="col">GEO</th>
          <th scope="col">Genome</th>
          <th scope="col">Track class</th>
          <th scope="col">Track type</th>
          <th scope="col">Cell type class</th>
          <th scope="col">Cell type</th>
        </tr>
      </thead>
      <tbody id="search-tbody"></tbody>
    </table>
  </div>
  <nav aria-label="Search pagination">
    <ul class="pagination pagination-sm justify-content-center mb-0">
      <li class="page-item" id="page-prev"><a class="page-link" href="#" role="button">Previous</a></li>
      <li class="page-item disabled"><span class="page-link" id="page-indicator">—</span></li>
      <li class="page-item" id="page-next"><a class="page-link" href="#" role="button">Next</a></li>
    </ul>
  </nav>
</div>
```

- [ ] **Step 3: Append search-page CSS rules to `public/css/style.css`**

Append the following to `/Users/inutano/repos/chip-atlas/public/css/style.css`:

```css

/* ===== Search page ===== */
#search-tbody td {
  vertical-align: middle;
}

#search-tbody a.expid-link {
  text-decoration: none;
  font-family: var(--bs-font-monospace, monospace);
}

#search-tbody a.expid-link:hover {
  text-decoration: underline;
}
```

- [ ] **Step 4: Create `frontend/pages/search.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/pages/search.ts`:

```typescript
// frontend/pages/search.ts
// Server-side paginated search. Replaces the legacy DataTables + 200MB JSON.

import { listGenomes, searchExperiments, type SearchExperiment, type SearchResult } from '../api/client'

const PAGE_SIZE = 20

const HEADERS = ['SRX', 'SRA', 'GEO', 'Genome', 'Track class', 'Track type', 'Cell type class', 'Cell type'] as const

interface State {
  query: string
  genome: string
  offset: number
  lastResult: SearchResult | null
}

const state: State = { query: '', genome: '', offset: 0, lastResult: null }

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

async function populateGenomeOptions(): Promise<void> {
  try {
    const genomes = await listGenomes()
    const select = $('search-genome') as HTMLSelectElement
    for (const [code, label] of Object.entries(genomes)) {
      const opt = document.createElement('option')
      opt.value = code
      opt.textContent = `${code} — ${label}`
      select.appendChild(opt)
    }
  } catch (err) {
    console.warn('Failed to load genomes:', err)
  }
}

function renderRow(row: SearchExperiment): HTMLTableRowElement {
  const tr = document.createElement('tr')

  const srxCell = document.createElement('td')
  const link = document.createElement('a')
  link.href = `/view?id=${encodeURIComponent(row.experiment_id)}`
  link.textContent = row.experiment_id
  link.className = 'expid-link'
  srxCell.appendChild(link)
  tr.appendChild(srxCell)

  const fields: Array<keyof SearchExperiment> = [
    'sra_id', 'geo_id', 'genome', 'track_class', 'track_subclass',
    'cell_type_class', 'cell_type_subclass',
  ]
  for (const f of fields) {
    const td = document.createElement('td')
    td.textContent = row[f] || ''
    tr.appendChild(td)
  }
  return tr
}

function renderResults(result: SearchResult): void {
  state.lastResult = result

  const tbody = $('search-tbody')
  tbody.replaceChildren(...result.experiments.map(renderRow))

  const start = result.total === 0 ? 0 : state.offset + 1
  const end = state.offset + result.returned
  $('search-summary').textContent = `${result.total.toLocaleString()} results · showing ${start}–${end}`

  $('page-indicator').textContent = `Page ${Math.floor(state.offset / PAGE_SIZE) + 1} of ${Math.max(1, Math.ceil(result.total / PAGE_SIZE))}`

  $('page-prev').classList.toggle('disabled', state.offset === 0)
  $('page-next').classList.toggle('disabled', state.offset + result.returned >= result.total)

  ;($('search-results-wrap') as HTMLElement).hidden = false
}

async function runSearch(): Promise<void> {
  const status = $('search-status')
  if (!state.query.trim()) {
    status.textContent = 'Enter a search query above.'
    ;($('search-results-wrap') as HTMLElement).hidden = true
    return
  }
  status.textContent = 'Searching…'
  try {
    const result = await searchExperiments(state.query, state.genome || undefined, PAGE_SIZE, state.offset)
    status.textContent = ''
    renderResults(result)
  } catch (err) {
    console.error(err)
    status.textContent = 'Search failed. Please try again.'
  }
}

function toTsv(rows: SearchExperiment[]): string {
  const lines = [HEADERS.join('\t')]
  for (const r of rows) {
    lines.push([
      r.experiment_id, r.sra_id, r.geo_id, r.genome,
      r.track_class, r.track_subclass, r.cell_type_class, r.cell_type_subclass,
    ].join('\t'))
  }
  return lines.join('\n') + '\n'
}

async function copyResultsToClipboard(): Promise<void> {
  if (!state.lastResult) return
  const tsv = toTsv(state.lastResult.experiments)
  try {
    await navigator.clipboard.writeText(tsv)
    const btn = $('copy-results')
    const original = btn.textContent || 'Copy'
    btn.textContent = 'Copied!'
    setTimeout(() => { btn.textContent = original }, 1500)
  } catch (err) {
    console.warn('Clipboard write failed:', err)
  }
}

function downloadTsv(): void {
  if (!state.lastResult) return
  const blob = new Blob([toTsv(state.lastResult.experiments)], { type: 'text/tab-separated-values' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `chip-atlas-search.tsv`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

function init(): void {
  populateGenomeOptions()

  const form = $('search-form') as HTMLFormElement
  form.addEventListener('submit', (e) => {
    e.preventDefault()
    state.query = ($('search-query') as HTMLInputElement).value
    state.genome = ($('search-genome') as HTMLSelectElement).value
    state.offset = 0
    runSearch()
  })

  $('page-prev').addEventListener('click', (e) => {
    e.preventDefault()
    if ($('page-prev').classList.contains('disabled')) return
    state.offset = Math.max(0, state.offset - PAGE_SIZE)
    runSearch()
  })
  $('page-next').addEventListener('click', (e) => {
    e.preventDefault()
    if ($('page-next').classList.contains('disabled')) return
    state.offset += PAGE_SIZE
    runSearch()
  })

  $('copy-results').addEventListener('click', copyResultsToClipboard)
  $('download-tsv').addEventListener('click', downloadTsv)
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 5: Build the TypeScript**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/search.js && echo "OK: search.js built" || echo "FAIL"
```

- [ ] **Step 6: Test the search page renders**

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
RACK_ENV=test ruby -e "
  require 'bundler/setup'
  require 'rack/test'
  require_relative 'app'
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get '/search'
  body = last_response.body
  puts \"Status: #{last_response.status}\"
  puts \"Has Bootstrap 5: #{body.include?('bootstrap5.min.css')}\"
  puts \"Has search form: #{body.include?(%q(id=\"search-form\"))}\"
  puts \"Has genome select: #{body.include?(%q(id=\"search-genome\"))}\"
  puts \"Has results table: #{body.include?(%q(id=\"search-tbody\"))}\"
  puts \"Has pagination nav: #{body.include?(%q(id=\"page-prev\"))}\"
  puts \"Has page_js script tag: #{body.include?('/js/search.js')}\"
"
```

Expected:
```
Status: 200
Has Bootstrap 5: true
Has search form: true
Has genome select: true
Has results table: true
Has pagination nav: true
Has page_js script tag: true
```

- [ ] **Step 7: Commit**

Stage `routes/pages.rb`, `views/search.erb`, `frontend/pages/search.ts`, `public/css/style.css`. (The compiled `public/js/search.js` is gitignored.)

```
Convert /search to ERB + TypeScript with server-side pagination

The legacy /search page loaded a 200MB ExperimentList.json into the
browser and rendered it with DataTables. Replace with a thin ERB
skeleton plus a TypeScript module that hits /api/search with
limit/offset, renders an HTML table, and offers prev/next pagination,
clipboard copy, and TSV download. The optional genome filter dropdown
is populated from /api/genomes on page load.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 3: Experiment Detail Page (`/view`)

**Files:**
- Create: `views/experiment.erb`
- Create: `frontend/pages/experiment.ts`
- Modify: `public/css/style.css` (append experiment-page rules)
- Modify: `routes/pages.rb` (fetch `@records`, set `@page_js = 'experiment'`)
- Build: `node esbuild.config.mjs`
- Test: `GET /view?id=SRX038634` returns 200 with expected DOM

The experiment detail page renders curated metadata and original metadata in panels, plus four action dropdowns (Visualize, Analyze, Download, Link Out). The dropdown URLs depend on the experiment's `track_class` (Bisulfite-Seq has a different file set than ChIP/ATAC) and on every genome the experiment appears in. The ERB renders the metadata panels server-side; the dropdowns are built client-side from a JSON-island data blob (the records array). This keeps the template simple.

- [ ] **Step 1: Update `/view` route to fetch records and set `@page_js`**

Edit `/Users/inutano/repos/chip-atlas/routes/pages.rb`. Find:

```ruby
        app.get '/view' do
          halt 400, json_response({ error: 'id parameter required' }) unless params[:id]
          @expid = params[:id].upcase
          if @expid.start_with?('GSM')
            srx = ChipAtlas::ExperimentSearch.gsm_to_srx(@expid)
            redirect "/view?id=#{srx}" if srx
          end
          redirect '/not_found', 404 unless ChipAtlas::Experiment.id_valid?(@expid)
          log_activity('view_experiment', { expid: @expid })
          @ncbi = ChipAtlas::SraService.new(@expid).fetch
          erb :experiment
        end
```

Replace with:

```ruby
        app.get '/view' do
          halt 400, json_response({ error: 'id parameter required' }) unless params[:id]
          @expid = params[:id].upcase
          if @expid.start_with?('GSM')
            srx = ChipAtlas::ExperimentSearch.gsm_to_srx(@expid)
            redirect "/view?id=#{srx}" if srx
          end
          redirect '/not_found', 404 unless ChipAtlas::Experiment.id_valid?(@expid)
          log_activity('view_experiment', { expid: @expid })
          @records = ChipAtlas::Experiment.record_by_experiment_id(@expid)
          @ncbi = ChipAtlas::SraService.new(@expid).fetch
          @page_js = 'experiment'
          erb :experiment
        end
```

- [ ] **Step 2: Create `views/experiment.erb`**

Write to `/Users/inutano/repos/chip-atlas/views/experiment.erb`:

```erb
<%
  @page_title = @expid
  @page_description = "Experimental attributes and details of processing for #{@expid}"
  @active_menu = nil
  metadata = @records[0]
%>
<script id="experiment-data" type="application/json"><%= { expid: @expid, records: @records }.to_json %></script>

<div class="row mb-3">
  <div class="col-md-10 offset-md-1">
    <div class="d-flex justify-content-between align-items-start flex-wrap gap-2 mb-3">
      <div>
        <h2 class="mb-1"><%= @expid %></h2>
        <small class="text-muted"><%= metadata[:title] != '-' ? metadata[:title] : 'No title provided' %></small>
      </div>
      <div class="btn-toolbar" role="toolbar" aria-label="Experiment actions">
        <div class="btn-group me-2" role="group">
          <button type="button" class="btn btn-primary dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false">Visualize</button>
          <ul class="dropdown-menu" id="visualize-menu"></ul>
        </div>
        <div class="btn-group me-2" role="group">
          <button type="button" class="btn btn-primary dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false">Analyze</button>
          <ul class="dropdown-menu" id="analyze-menu"></ul>
        </div>
        <div class="btn-group me-2" role="group">
          <button type="button" class="btn btn-primary dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false">Download</button>
          <ul class="dropdown-menu" id="download-menu"></ul>
        </div>
        <div class="btn-group" role="group">
          <button type="button" class="btn btn-primary dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false">Link Out</button>
          <ul class="dropdown-menu dropdown-menu-end" id="linkout-menu"></ul>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="row mb-3">
  <div class="col-md-10 offset-md-1">
    <div class="card">
      <div class="card-header"><h5 class="mb-0">Sample Information Curated by ChIP-Atlas</h5></div>
      <div class="card-body">
        <div class="row">
          <div class="col-md-6">
            <h6>Antigen Information</h6>
            <dl class="row mb-0">
              <dt class="col-sm-5">Antigen Class</dt><dd class="col-sm-7"><%= metadata[:track_class] %></dd>
              <dt class="col-sm-5">Antigen</dt><dd class="col-sm-7"><%= metadata[:track_subclass] %></dd>
            </dl>
          </div>
          <div class="col-md-6">
            <h6>Cell Type Information</h6>
            <dl class="row mb-0">
              <dt class="col-sm-5">Cell Type Class</dt><dd class="col-sm-7"><%= metadata[:cell_type_class] %></dd>
              <dt class="col-sm-5">Cell Type</dt><dd class="col-sm-7"><%= metadata[:cell_type_subclass] %></dd>
              <% metadata[:cell_type_subclass_info].to_s.split('|').each do |kv| %>
                <% k, v = kv.split('=', 2) %>
                <% next if k.nil? || k.strip.empty? %>
                <dt class="col-sm-5"><%= k %></dt><dd class="col-sm-7"><%= v %></dd>
              <% end %>
            </dl>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="row mb-3">
  <div class="col-md-10 offset-md-1">
    <div class="card">
      <div class="card-header"><h5 class="mb-0">Original Experimental Metadata</h5></div>
      <div class="card-body">
        <h6>Sample Attributes</h6>
        <% attr_str = metadata[:attributes].to_s.strip %>
        <% if attr_str.empty? %>
          <p class="text-muted">No sample attributes were provided by the original submitter.</p>
        <% else %>
          <dl class="row mb-3">
            <% attr_str.split("\t").each do |kv| %>
              <% k, v = kv.split('=', 2) %>
              <% next if k.nil? || k.strip.empty? %>
              <dt class="col-sm-4"><%= k %></dt><dd class="col-sm-8"><%= v %></dd>
            <% end %>
          </dl>
        <% end %>

        <hr>

        <div class="row">
          <div class="col-md-6">
            <h6>Sequenced DNA Library</h6>
            <% if @ncbi[:library_description].values.uniq == [''] %>
              <p class="text-muted">No library information was found.</p>
            <% else %>
              <dl class="row mb-0">
                <% @ncbi[:library_description].each_pair do |k, v| %>
                  <% next if v.to_s.empty? %>
                  <dt class="col-sm-5"><%= k %></dt><dd class="col-sm-7"><%= v %></dd>
                <% end %>
              </dl>
            <% end %>
          </div>
          <div class="col-md-6">
            <h6>Sequencing Platform</h6>
            <% if @ncbi[:platform_information].values.uniq == [''] %>
              <p class="text-muted">No platform information was found.</p>
            <% else %>
              <dl class="row mb-0">
                <% @ncbi[:platform_information].each_pair do |k, v| %>
                  <% next if v.to_s.empty? %>
                  <dt class="col-sm-5"><%= k %></dt><dd class="col-sm-7"><%= v %></dd>
                <% end %>
              </dl>
            <% end %>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="row mb-3">
  <div class="col-md-10 offset-md-1">
    <div class="card">
      <div class="card-header d-flex justify-content-between align-items-center">
        <h5 class="mb-0">Read Processing Pipeline</h5>
        <a href="https://github.com/inutano/chip-atlas/wiki#2-primary-processing" target="_blank" rel="noopener noreferrer" class="small">Pipeline docs</a>
      </div>
      <div class="card-body">
        <div class="row">
          <% @records.each do |record| %>
            <% readinfo = record[:read_info].to_s.split(',') %>
            <div class="col-md-6 mb-3">
              <h6 class="text-muted"><%= record[:genome] %></h6>
              <dl class="row mb-0">
                <% if metadata[:track_class] != 'Bisulfite-Seq' %>
                  <dt class="col-sm-7">Number of total reads</dt><dd class="col-sm-5"><%= readinfo[0] %></dd>
                  <dt class="col-sm-7">Reads aligned (%)</dt><dd class="col-sm-5"><%= readinfo[1] %></dd>
                  <dt class="col-sm-7">Duplicates removed (%)</dt><dd class="col-sm-5"><%= readinfo[2] %></dd>
                  <dt class="col-sm-7">Number of peaks</dt><dd class="col-sm-5"><%= readinfo[3] %> (qval &lt; 1E-05)</dd>
                <% else %>
                  <dt class="col-sm-7">Number of total reads</dt><dd class="col-sm-5"><%= readinfo[0] %></dd>
                  <dt class="col-sm-7">Reads aligned (%)</dt><dd class="col-sm-5"><%= readinfo[1] %></dd>
                  <dt class="col-sm-7">Coverage rate (×)</dt><dd class="col-sm-5"><%= readinfo[2] %></dd>
                  <dt class="col-sm-7">Number of hyper MRs</dt><dd class="col-sm-5"><%= readinfo[3] %> (qval &lt; 1E-05)</dd>
                <% end %>
              </dl>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Append experiment-page CSS rules to `public/css/style.css`**

Append the following to `/Users/inutano/repos/chip-atlas/public/css/style.css`:

```css

/* ===== Experiment detail page ===== */
.dropdown-menu .dropdown-header {
  font-weight: 600;
  color: #495057;
}

.dropdown-menu.dropdown-menu-end {
  min-width: 14rem;
}
```

- [ ] **Step 4: Create `frontend/pages/experiment.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/pages/experiment.ts`:

```typescript
// frontend/pages/experiment.ts
// Builds the four action dropdowns (Visualize, Analyze, Download, Link Out)
// for the experiment detail page. Reads experiment records from a JSON island.

import type { ExperimentRecord } from '../api/client'

interface PageData {
  expid: string
  records: ExperimentRecord[]
}

const DATA_BASE = 'https://chip-atlas.dbcls.jp/data'
const IGV_BASE = 'http://localhost:60151/load?file=https://chip-atlas.dbcls.jp/data'
const QVALS = ['05', '10', '20'] as const
const TSS_KB = ['1', '5', '10'] as const

function readData(): PageData | null {
  const el = document.getElementById('experiment-data')
  if (!el || !el.textContent) return null
  try {
    return JSON.parse(el.textContent) as PageData
  } catch (err) {
    console.error('Failed to parse experiment-data:', err)
    return null
  }
}

function sanitize(s: string): string {
  return s.replace(/[^a-zA-Z0-9_-]/g, '_')
}

function header(text: string): HTMLLIElement {
  const li = document.createElement('li')
  const h = document.createElement('h6')
  h.className = 'dropdown-header'
  h.textContent = text
  li.appendChild(h)
  return li
}

function divider(): HTMLLIElement {
  const li = document.createElement('li')
  const hr = document.createElement('hr')
  hr.className = 'dropdown-divider'
  li.appendChild(hr)
  return li
}

function item(href: string, label: string, opts: { download?: string; external?: boolean } = {}): HTMLLIElement {
  const li = document.createElement('li')
  const a = document.createElement('a')
  a.className = 'dropdown-item'
  a.href = href
  a.textContent = label
  if (opts.download) a.setAttribute('download', opts.download)
  if (opts.external) {
    a.target = '_blank'
    a.rel = 'noopener noreferrer'
  }
  li.appendChild(a)
  return li
}

function igvName(record: ExperimentRecord, suffix: string): string {
  const base = `${record.track_subclass} (@ ${record.cell_type_subclass}) ${record.experiment_id}${suffix}`.replace(/, /g, '_')
  return encodeURIComponent(base)
}

function buildVisualizeMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  const isBisulfite = data.records[0].track_class === 'Bisulfite-Seq'

  data.records.forEach((record, i) => {
    items.push(header(`For ${record.genome}`))
    const g = record.genome
    const expid = data.expid

    if (!isBisulfite) {
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bw/${expid}.bw&genome=${g}&name=${igvName(record, '')}`,
        'BigWig',
      ))
      for (const q of QVALS) {
        items.push(item(
          `${IGV_BASE}/${g}/eachData/bb${q}/${expid}.${q}.bb&genome=${g}&name=${igvName(record, ` (1E-${q})`)}`,
          `Peak-call (q < 1E-${q})`,
        ))
      }
    } else {
      const cl = record.cell_type_subclass
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/methyl/${expid}.methyl.bw&genome=${g}&name=${encodeURIComponent(`Methylation rate (@ ${cl}) ${expid}`)}`,
        'BigWig (Methylation rate)',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/cover/${expid}.cover.bw&genome=${g}&name=${encodeURIComponent(`Coverage rate (@ ${cl}) ${expid}`)}`,
        'BigWig (Coverage)',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/hmr/BigBed/${expid}.hmr.bb&genome=${g}&name=${encodeURIComponent(`Hypo MR (@ ${cl}) ${expid}`)}`,
        'Hypo MR',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/pmd/BigBed/${expid}.pmd.bb&genome=${g}&name=${encodeURIComponent(`Partial MR (@ ${cl}) ${expid}`)}`,
        'Partial MR',
      ))
      items.push(item(
        `${IGV_BASE}/${g}/eachData/bs/hypermr/BigBed/${expid}.hypermr.bb&genome=${g}&name=${encodeURIComponent(`Hyper MR (@ ${cl}) ${expid}`)}`,
        'Hyper MR',
      ))
    }
    if (i < data.records.length - 1) items.push(divider())
  })
  return items
}

function buildAnalyzeMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  data.records.forEach((record, i) => {
    items.push(header(`For ${record.genome}`))
    items.push(item(`${DATA_BASE}/${record.genome}/colo/${data.expid}.html`, 'Colocalization'))
    for (const kb of TSS_KB) {
      items.push(item(`${DATA_BASE}/${record.genome}/target/${data.expid}.${kb}.html`, `Target Genes (TSS ± ${kb}kb)`))
    }
    if (i < data.records.length - 1) items.push(divider())
  })
  return items
}

function buildDownloadMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  const isBisulfite = data.records[0].track_class === 'Bisulfite-Seq'

  data.records.forEach((record, i) => {
    items.push(header(`For ${record.genome}`))
    const g = record.genome
    const expid = data.expid
    const fname = `${g}_${sanitize(record.track_subclass)}_${sanitize(record.cell_type_subclass)}_${expid}`

    if (!isBisulfite) {
      items.push(item(`${DATA_BASE}/${g}/eachData/bw/${expid}.bw`, 'BigWig', { download: `${fname}.bw` }))
      for (const q of QVALS) {
        items.push(item(
          `${DATA_BASE}/${g}/eachData/bed${q}/${expid}.${q}.bed`,
          `Peak-call (q < 1E-${q})`,
          { download: `${fname}.${q}.bed` },
        ))
      }
    } else {
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/methyl/${expid}.methyl.bw`, 'BigWig (Methylation rate)'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/cover/${expid}.cover.bw`, 'BigWig (Coverage)'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/hmr/BigBed/${expid}.hmr.bb`, 'Hypo MR'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/pmd/BigBed/${expid}.pmd.bb`, 'Partial MR'))
      items.push(item(`${DATA_BASE}/${g}/eachData/bs/hypermr/BigBed/${expid}.hypermr.bb`, 'Hyper MR'))
    }
    if (i < data.records.length - 1) items.push(divider())
  })
  return items
}

function buildLinkOutMenu(data: PageData): HTMLElement[] {
  const items: HTMLElement[] = []
  const m = data.records[0]
  const expid = data.expid
  const antigen = m.track_subclass
  const celltype = m.cell_type_subclass

  items.push(header('Sequence Read Archive'))
  items.push(item(`https://ddbj.nig.ac.jp/search/entry/sra-experiment/${expid}`, 'DDBJ Search', { external: true }))
  items.push(item(`https://www.ncbi.nlm.nih.gov/sra/?term=${expid}`, 'NCBI SRA', { external: true }))
  items.push(item(`https://www.ebi.ac.uk/ena/browser/view/${expid}`, 'ENA', { external: true }))
  items.push(divider())

  items.push(header(`Antigen: ${antigen}`))
  items.push(item(`https://www.wikigenes.org/?search=${encodeURIComponent(antigen)}`, 'wikigenes', { external: true }))
  items.push(item(`http://pdbj.org/mine/search?query=${encodeURIComponent(antigen)}`, 'PDBj', { external: true }))
  items.push(divider())

  items.push(header(`Cell Type: ${celltype}`))
  items.push(item(`http://www.atcc.org/Search_Results.aspx?searchTerms=${encodeURIComponent(celltype)}`, 'ATCC', { external: true }))
  items.push(item(`https://www.ncbi.nlm.nih.gov/mesh/?term=${encodeURIComponent(celltype)}`, 'MeSH', { external: true }))
  items.push(item(`http://www2.brc.riken.jp/lab/cell/list.cgi?skey=${encodeURIComponent(celltype)}`, 'RIKEN BRC', { external: true }))

  if (m.genome === 'hg19' || m.genome === 'hg38') {
    items.push(divider())
    items.push(header('Variation'))
    items.push(item(`https://togovar.biosciencedbc.jp/?term=${encodeURIComponent(antigen)}`, 'TogoVar', { external: true }))
  }
  return items
}

function fill(menuId: string, children: HTMLElement[]): void {
  const ul = document.getElementById(menuId)
  if (!ul) return
  ul.replaceChildren(...children)
}

function init(): void {
  const data = readData()
  if (!data || data.records.length === 0) return
  fill('visualize-menu', buildVisualizeMenu(data))
  fill('analyze-menu', buildAnalyzeMenu(data))
  fill('download-menu', buildDownloadMenu(data))
  fill('linkout-menu', buildLinkOutMenu(data))
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 5: Build the TypeScript**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/experiment.js && echo "OK: experiment.js built" || echo "FAIL"
```

- [ ] **Step 6: Test the experiment page renders**

This test depends on the database having `SRX038634` in it (the test DB does). The NCBI fetch in `SraService` will likely fail in test mode (network unavailable) and fall back to `error_metadata` — that is fine; we are testing the ERB structure, not the data.

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
RACK_ENV=test ruby -e "
  require 'bundler/setup'
  require 'rack/test'
  require_relative 'app'
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get '/view?id=SRX038634'
  body = last_response.body
  puts \"Status: #{last_response.status}\"
  puts \"Has experiment-data JSON island: #{body.include?(%q(id=\"experiment-data\"))}\"
  puts \"Has SRX038634 heading: #{body.include?('SRX038634')}\"
  puts \"Has Visualize dropdown: #{body.include?(%q(id=\"visualize-menu\"))}\"
  puts \"Has Analyze dropdown: #{body.include?(%q(id=\"analyze-menu\"))}\"
  puts \"Has Download dropdown: #{body.include?(%q(id=\"download-menu\"))}\"
  puts \"Has Link Out dropdown: #{body.include?(%q(id=\"linkout-menu\"))}\"
  puts \"Has experiment.js: #{body.include?('/js/experiment.js')}\"
  puts \"Has Sample Information panel: #{body.include?('Sample Information Curated by ChIP-Atlas')}\"
  puts \"Has Pipeline panel: #{body.include?('Read Processing Pipeline')}\"
"
```

Expected:
```
Status: 200
Has experiment-data JSON island: true
Has SRX038634 heading: true
Has Visualize dropdown: true
Has Analyze dropdown: true
Has Download dropdown: true
Has Link Out dropdown: true
Has experiment.js: true
Has Sample Information panel: true
Has Pipeline panel: true
```

- [ ] **Step 7: Commit**

Stage `routes/pages.rb`, `views/experiment.erb`, `frontend/pages/experiment.ts`, `public/css/style.css`. (Compiled `public/js/experiment.js` is gitignored.)

```
Convert /view to ERB + TypeScript with JSON-island dropdowns

The experiment detail page now renders metadata panels server-side
and embeds the records array as a JSON island. The four action
dropdowns (Visualize, Analyze, Download, Link Out) are built by
TypeScript at DOMContentLoaded — branching on track_class to pick
the right file set (BigWig + peak-call BEDs for ChIP/ATAC, methyl/
cover/hmr/pmd/hypermr for Bisulfite-Seq), with a section per genome
the experiment appears in. External links use rel=noopener noreferrer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 4: GenomeTabs Component

**Files:**
- Create: `frontend/components/genome-tabs.ts`
- Test: `npx tsc --project frontend/tsconfig.json --noEmit` and a smoke test in a temporary scratch page

Component spec (from design doc):

```typescript
GenomeTabs.init(container: HTMLElement, genomes: Record<string, string>)
// Listens for: container.addEventListener('genome-change', (e) => e.detail.genome)
```

The component renders Bootstrap 5 `nav-tabs` markup inside `container`. The selected genome is persisted in the URL hash (`#genome=hg38`). On selection change, a `genome-change` CustomEvent with `detail.genome` is dispatched on `container`.

- [ ] **Step 1: Create `frontend/components/genome-tabs.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/components/genome-tabs.ts`:

```typescript
// frontend/components/genome-tabs.ts
// Bootstrap 5 nav-tabs for genome selection. Persists choice in #genome=<code>.

export interface GenomeChangeDetail {
  genome: string
}

function readGenomeFromHash(): string | null {
  const match = window.location.hash.match(/genome=([\w-]+)/)
  return match ? match[1] : null
}

function writeGenomeToHash(genome: string): void {
  const hash = window.location.hash.replace(/(^#?|&)genome=[\w-]+/, '').replace(/^&/, '')
  const next = hash ? `#${hash}&genome=${genome}` : `#genome=${genome}`
  history.replaceState(null, '', next)
}

function dispatchChange(container: HTMLElement, genome: string): void {
  container.dispatchEvent(new CustomEvent<GenomeChangeDetail>('genome-change', {
    detail: { genome },
    bubbles: false,
  }))
}

function pickInitialGenome(genomes: Record<string, string>): string {
  const fromHash = readGenomeFromHash()
  if (fromHash && fromHash in genomes) return fromHash
  return Object.keys(genomes)[0] || ''
}

export const GenomeTabs = {
  init(container: HTMLElement, genomes: Record<string, string>): void {
    const codes = Object.keys(genomes)
    if (codes.length === 0) {
      container.innerHTML = ''
      return
    }

    const initial = pickInitialGenome(genomes)

    const ul = document.createElement('ul')
    ul.className = 'nav nav-tabs mb-3'
    ul.setAttribute('role', 'tablist')

    for (const code of codes) {
      const li = document.createElement('li')
      li.className = 'nav-item'
      li.setAttribute('role', 'presentation')

      const button = document.createElement('button')
      button.type = 'button'
      button.className = 'nav-link' + (code === initial ? ' active' : '')
      button.setAttribute('role', 'tab')
      button.setAttribute('aria-selected', code === initial ? 'true' : 'false')
      button.dataset.genome = code
      button.textContent = code
      button.title = genomes[code]

      button.addEventListener('click', () => {
        ul.querySelectorAll<HTMLButtonElement>('button.nav-link').forEach((b) => {
          const active = b === button
          b.classList.toggle('active', active)
          b.setAttribute('aria-selected', active ? 'true' : 'false')
        })
        writeGenomeToHash(code)
        dispatchChange(container, code)
      })

      li.appendChild(button)
      ul.appendChild(li)
    }

    container.replaceChildren(ul)

    // Emit an initial event so callers can render the starting state.
    if (initial) {
      writeGenomeToHash(initial)
      dispatchChange(container, initial)
    }
  },

  getSelected(container: HTMLElement): string | null {
    const active = container.querySelector<HTMLButtonElement>('button.nav-link.active')
    return active?.dataset.genome ?? null
  },
}
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd /Users/inutano/repos/chip-atlas && npx tsc --project frontend/tsconfig.json --noEmit
```

Expected: exit 0.

- [ ] **Step 3: Smoke test by building**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
```

Expected: build succeeds. The component file is not an entry point but should be importable by future page modules — tsc and esbuild both validate the syntax.

- [ ] **Step 4: Commit**

Stage `frontend/components/genome-tabs.ts`. HEREDOC:

```
Add GenomeTabs shared component

Renders Bootstrap 5 nav-tabs for genome selection, persists the
choice in the URL fragment as #genome=<code>, and dispatches a
genome-change CustomEvent on the container with detail.genome.
Designed for use on Peak Browser, Enrichment Analysis, Diff Analysis,
Target Genes, and Colo pages (Plan 3).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 5: Autocomplete Component

**Files:**
- Create: `frontend/components/autocomplete.ts`
- Modify: `public/css/style.css` (append autocomplete styles)
- Test: `npx tsc` and build verification

Component spec:

```typescript
Autocomplete.init(input: HTMLInputElement, items: string[], onSelect: (value: string) => void)
Autocomplete.setItems(items: string[])
```

Substring matching (case-insensitive). Keyboard navigation: ArrowDown, ArrowUp, Enter, Escape. Mouse: click to select, blur closes dropdown.

- [ ] **Step 1: Create `frontend/components/autocomplete.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/components/autocomplete.ts`:

```typescript
// frontend/components/autocomplete.ts
// Text input with substring-matching dropdown suggestions.
// Keyboard navigation: ArrowDown, ArrowUp, Enter, Escape.

interface Instance {
  input: HTMLInputElement
  menu: HTMLUListElement
  items: string[]
  filtered: string[]
  active: number
  onSelect: (value: string) => void
}

const MAX_RESULTS = 50
const registry = new WeakMap<HTMLInputElement, Instance>()

function buildMenu(): HTMLUListElement {
  const menu = document.createElement('ul')
  menu.className = 'list-group autocomplete-menu'
  menu.setAttribute('role', 'listbox')
  menu.style.display = 'none'
  return menu
}

function placeMenu(input: HTMLInputElement, menu: HTMLUListElement): void {
  const parent = input.parentElement
  if (!parent) return
  if (getComputedStyle(parent).position === 'static') parent.style.position = 'relative'
  if (menu.parentElement !== parent) parent.appendChild(menu)

  menu.style.position = 'absolute'
  menu.style.top = `${input.offsetTop + input.offsetHeight}px`
  menu.style.left = `${input.offsetLeft}px`
  menu.style.width = `${input.offsetWidth}px`
  menu.style.zIndex = '1050'
  menu.style.maxHeight = '320px'
  menu.style.overflowY = 'auto'
}

function filter(items: string[], query: string): string[] {
  const q = query.trim().toLowerCase()
  if (!q) return items.slice(0, MAX_RESULTS)
  const out: string[] = []
  for (const item of items) {
    if (item.toLowerCase().includes(q)) {
      out.push(item)
      if (out.length >= MAX_RESULTS) break
    }
  }
  return out
}

function render(inst: Instance): void {
  const { menu, filtered, active } = inst
  if (filtered.length === 0) {
    menu.style.display = 'none'
    menu.replaceChildren()
    return
  }
  menu.replaceChildren(...filtered.map((value, i) => {
    const li = document.createElement('li')
    li.className = 'list-group-item list-group-item-action' + (i === active ? ' active' : '')
    li.setAttribute('role', 'option')
    li.dataset.index = String(i)
    li.style.cursor = 'pointer'
    li.textContent = value
    li.addEventListener('mousedown', (e) => {
      e.preventDefault()
      select(inst, i)
    })
    return li
  }))
  menu.style.display = 'block'
  placeMenu(inst.input, menu)
}

function select(inst: Instance, index: number): void {
  const value = inst.filtered[index]
  if (value == null) return
  inst.input.value = value
  inst.onSelect(value)
  close(inst)
}

function open(inst: Instance): void {
  inst.filtered = filter(inst.items, inst.input.value)
  inst.active = inst.filtered.length > 0 ? 0 : -1
  render(inst)
}

function close(inst: Instance): void {
  inst.filtered = []
  inst.active = -1
  inst.menu.style.display = 'none'
}

function move(inst: Instance, delta: number): void {
  if (inst.filtered.length === 0) return
  inst.active = (inst.active + delta + inst.filtered.length) % inst.filtered.length
  render(inst)
}

function attachKeyboard(inst: Instance): void {
  inst.input.addEventListener('keydown', (e) => {
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault()
        if (inst.menu.style.display === 'none') open(inst)
        else move(inst, 1)
        break
      case 'ArrowUp':
        e.preventDefault()
        move(inst, -1)
        break
      case 'Enter':
        if (inst.active >= 0) {
          e.preventDefault()
          select(inst, inst.active)
        }
        break
      case 'Escape':
        close(inst)
        break
    }
  })
}

export const Autocomplete = {
  init(input: HTMLInputElement, items: string[], onSelect: (value: string) => void): void {
    const menu = buildMenu()
    const inst: Instance = { input, menu, items, filtered: [], active: -1, onSelect }
    registry.set(input, inst)

    input.setAttribute('autocomplete', 'off')
    input.setAttribute('role', 'combobox')
    input.setAttribute('aria-autocomplete', 'list')

    input.addEventListener('focus', () => open(inst))
    input.addEventListener('input', () => open(inst))
    input.addEventListener('blur', () => {
      // Delay close so a click on the menu can fire first.
      setTimeout(() => close(inst), 100)
    })

    attachKeyboard(inst)
  },

  setItems(input: HTMLInputElement, items: string[]): void {
    const inst = registry.get(input)
    if (!inst) return
    inst.items = items
    if (document.activeElement === input) open(inst)
  },
}
```

- [ ] **Step 2: Append autocomplete CSS rules to `public/css/style.css`**

Append the following:

```css

/* ===== Autocomplete component ===== */
.autocomplete-menu {
  margin-top: 0.25rem;
  box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
}

.autocomplete-menu .list-group-item {
  padding: 0.4rem 0.75rem;
}

.autocomplete-menu .list-group-item.active {
  background-color: var(--bs-primary);
  border-color: var(--bs-primary);
  color: white;
}
```

- [ ] **Step 3: Verify TypeScript compiles + build**

```bash
cd /Users/inutano/repos/chip-atlas && npx tsc --project frontend/tsconfig.json --noEmit && node esbuild.config.mjs
```

Expected: both exit 0.

- [ ] **Step 4: Commit**

Stage `frontend/components/autocomplete.ts` and `public/css/style.css`.

```
Add Autocomplete shared component

Substring-matching dropdown for text inputs. Replaces the legacy
Typeahead.js + Flexselect + LiquidMetal stack with ~150 lines of TS.
Keyboard navigation (ArrowDown, ArrowUp, Enter, Escape), mouse
click-to-select, and a setItems API so upstream selection changes can
update the suggestion pool. Designed for use on Peak Browser, Target
Genes, Colo, and Enrichment Analysis pages (Plan 3).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 6: FacetFilter Component

**Files:**
- Create: `frontend/components/facet-filter.ts`
- Test: `npx tsc` and build verification

Component spec:

```typescript
FacetFilter.init(container: HTMLElement, genome: string)
FacetFilter.getCondition() → { genome, track_class, track_subclass, cell_type_class, cell_type_subclass, qval }
FacetFilter.setGenome(genome: string)  // re-fetch counts for the new genome
```

Cascading dropdowns: genome (passed in) → track_class → cell_type_class → track_subclass / cell_type_subclass → qval. **Bidirectional counts:** selecting a cell type re-fetches track_class counts filtered by that cell type, and vice versa. This matches the current Enrichment Analysis behavior. Each `<select>` shows `<option>{label} (n=count)</option>` for items with non-null counts.

- [ ] **Step 1: Create `frontend/components/facet-filter.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/components/facet-filter.ts`:

```typescript
// frontend/components/facet-filter.ts
// Cascading dropdowns with bidirectional count updates.
// genome → track_class ⇄ cell_type_class → track_subclass + cell_type_subclass → qval

import {
  listTrackClasses,
  listCellTypeClasses,
  listTrackSubclasses,
  listCellTypeSubclasses,
  getQvalRange,
  type ClassificationItem,
} from '../api/client'

export interface FacetCondition {
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  qval: string
}

interface Instance {
  container: HTMLElement
  genome: string
  trackClass: HTMLSelectElement
  cellTypeClass: HTMLSelectElement
  trackSubclass: HTMLSelectElement
  cellTypeSubclass: HTMLSelectElement
  qval: HTMLSelectElement
}

const registry = new WeakMap<HTMLElement, Instance>()

function labelWithCount(item: ClassificationItem): string {
  return item.count == null ? item.label : `${item.label} (n=${item.count.toLocaleString()})`
}

function fillSelect(select: HTMLSelectElement, items: ClassificationItem[]): void {
  const previous = select.value
  select.replaceChildren(...items.map((it) => {
    const opt = document.createElement('option')
    opt.value = it.id
    opt.textContent = labelWithCount(it)
    return opt
  }))
  if (items.some((it) => it.id === previous)) {
    select.value = previous
  }
}

function makeLabeledSelect(id: string, labelText: string): { wrap: HTMLDivElement; select: HTMLSelectElement } {
  const wrap = document.createElement('div')
  wrap.className = 'mb-2'

  const label = document.createElement('label')
  label.htmlFor = id
  label.className = 'form-label small text-muted mb-1'
  label.textContent = labelText

  const select = document.createElement('select')
  select.id = id
  select.className = 'form-select form-select-sm'

  wrap.appendChild(label)
  wrap.appendChild(select)
  return { wrap, select }
}

async function loadTrackClasses(inst: Instance): Promise<void> {
  const cell = inst.cellTypeClass.value || undefined
  const items = await listTrackClasses(inst.genome, cell)
  fillSelect(inst.trackClass, items)
}

async function loadCellTypeClasses(inst: Instance): Promise<void> {
  const items = await listCellTypeClasses(inst.genome, inst.trackClass.value)
  fillSelect(inst.cellTypeClass, items)
}

async function loadTrackSubclasses(inst: Instance): Promise<void> {
  const items = await listTrackSubclasses(inst.genome, inst.trackClass.value, inst.cellTypeClass.value || undefined)
  fillSelect(inst.trackSubclass, items)
}

async function loadCellTypeSubclasses(inst: Instance): Promise<void> {
  const items = await listCellTypeSubclasses(inst.genome, inst.trackClass.value, inst.cellTypeClass.value || undefined)
  fillSelect(inst.cellTypeSubclass, items)
}

async function loadQvalRange(inst: Instance): Promise<void> {
  try {
    const values = await getQvalRange()
    inst.qval.replaceChildren(...values.map((v) => {
      const opt = document.createElement('option')
      opt.value = v
      opt.textContent = v
      return opt
    }))
  } catch (err) {
    console.warn('Failed to load qval range:', err)
  }
}

async function initialLoad(inst: Instance): Promise<void> {
  // Sequential: cell_type_classes requires a non-empty track_class. On init both
  // selects start empty, so we must seed track_class first, then load the rest.
  await loadTrackClasses(inst)
  await Promise.all([loadCellTypeClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

async function reloadOnTrackChange(inst: Instance): Promise<void> {
  await Promise.all([loadCellTypeClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

async function reloadOnCellChange(inst: Instance): Promise<void> {
  await Promise.all([loadTrackClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

function attachHandlers(inst: Instance): void {
  inst.trackClass.addEventListener('change', async () => {
    // bidirectional: refresh cell types and both subclass lists
    await reloadOnTrackChange(inst)
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.cellTypeClass.addEventListener('change', async () => {
    await reloadOnCellChange(inst)
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.trackSubclass.addEventListener('change', () => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.cellTypeSubclass.addEventListener('change', () => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.qval.addEventListener('change', () => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
}

export const FacetFilter = {
  async init(container: HTMLElement, genome: string): Promise<void> {
    const trackClass = makeLabeledSelect('facet-track-class', 'Track type class')
    const cellTypeClass = makeLabeledSelect('facet-cell-type-class', 'Cell type class')
    const trackSubclass = makeLabeledSelect('facet-track-subclass', 'Track type')
    const cellTypeSubclass = makeLabeledSelect('facet-cell-type-subclass', 'Cell type')
    const qval = makeLabeledSelect('facet-qval', 'Threshold (qval)')

    container.replaceChildren(
      trackClass.wrap, cellTypeClass.wrap, trackSubclass.wrap, cellTypeSubclass.wrap, qval.wrap,
    )

    const inst: Instance = {
      container,
      genome,
      trackClass: trackClass.select,
      cellTypeClass: cellTypeClass.select,
      trackSubclass: trackSubclass.select,
      cellTypeSubclass: cellTypeSubclass.select,
      qval: qval.select,
    }
    registry.set(container, inst)

    attachHandlers(inst)

    await Promise.all([initialLoad(inst), loadQvalRange(inst)])
    container.dispatchEvent(new CustomEvent('facet-change'))
  },

  getCondition(container: HTMLElement): FacetCondition | null {
    const inst = registry.get(container)
    if (!inst) return null
    return {
      genome: inst.genome,
      track_class: inst.trackClass.value,
      track_subclass: inst.trackSubclass.value,
      cell_type_class: inst.cellTypeClass.value,
      cell_type_subclass: inst.cellTypeSubclass.value,
      qval: inst.qval.value,
    }
  },

  async setGenome(container: HTMLElement, genome: string): Promise<void> {
    const inst = registry.get(container)
    if (!inst) return
    inst.genome = genome
    await initialLoad(inst)
    container.dispatchEvent(new CustomEvent('facet-change'))
  },
}
```

- [ ] **Step 2: Verify TypeScript compiles + build**

```bash
cd /Users/inutano/repos/chip-atlas && npx tsc --project frontend/tsconfig.json --noEmit && node esbuild.config.mjs
```

Expected: both exit 0.

- [ ] **Step 3: Commit**

Stage `frontend/components/facet-filter.ts`.

```
Add FacetFilter shared component

Cascading dropdowns (track class, cell type class, track subclass,
cell type subclass, qval) with bidirectional count updates: changing
either the track class or the cell type class re-fetches the other
side's counts filtered by the new selection. Emits a facet-change
CustomEvent on the container so page modules can react. Designed for
Peak Browser, Enrichment Analysis, and Diff Analysis (Plan 3).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 7: JobTracker Component

**Files:**
- Create: `frontend/components/job-tracker.ts`
- Test: `npx tsc` and build verification

Component spec:

```typescript
JobTracker.init(container: HTMLElement, jobId: string, backend: string)
```

Polls `/jobs/:id/status` every 10 seconds. Renders:
- Status badge (queued / running / finished / error / backend_unavailable)
- Live elapsed time (HH:MM:SS) since `init()` was called
- "View log" button — fetches `/jobs/:id/log` and displays in a collapsible `<pre>` block
- When status flips to a finished state, fetches `/jobs/:id/result` and renders the URLs as download links

Stops polling when status is one of `finished`, `error`, `backend_unavailable`.

- [ ] **Step 1: Create `frontend/components/job-tracker.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/components/job-tracker.ts`:

```typescript
// frontend/components/job-tracker.ts
// Polls /jobs/:id/status, shows live elapsed time, displays result links + log.

import { getJobStatus, getJobResult, getJobLog, type JobStatus, type JobResult } from '../api/client'

const POLL_INTERVAL_MS = 10_000
const TERMINAL_STATUSES = new Set(['finished', 'completed', 'success', 'error', 'failed', 'backend_unavailable'])

interface Instance {
  container: HTMLElement
  jobId: string
  backend: string
  startedAt: number
  pollHandle: number | null
  clockHandle: number | null
  badge: HTMLSpanElement
  elapsedEl: HTMLSpanElement
  resultsEl: HTMLDivElement
  logEl: HTMLPreElement
  logButton: HTMLButtonElement
}

function pad(n: number): string {
  return n.toString().padStart(2, '0')
}

function formatElapsed(ms: number): string {
  const total = Math.floor(ms / 1000)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return `${pad(h)}:${pad(m)}:${pad(s)}`
}

function badgeClass(status: string): string {
  if (status === 'finished' || status === 'completed' || status === 'success') return 'badge bg-success'
  if (status === 'error' || status === 'failed' || status === 'backend_unavailable') return 'badge bg-danger'
  if (status === 'running') return 'badge bg-primary'
  return 'badge bg-secondary'
}

function build(inst: Pick<Instance, 'jobId' | 'backend'>): {
  root: HTMLDivElement
  badge: HTMLSpanElement
  elapsed: HTMLSpanElement
  results: HTMLDivElement
  logButton: HTMLButtonElement
  log: HTMLPreElement
} {
  const root = document.createElement('div')

  const head = document.createElement('div')
  head.className = 'd-flex align-items-center gap-3 mb-3 flex-wrap'

  const idSpan = document.createElement('span')
  idSpan.className = 'small text-muted'
  idSpan.textContent = `Job ${inst.jobId} on ${inst.backend.toUpperCase()}`

  const badge = document.createElement('span')
  badge.className = 'badge bg-secondary'
  badge.textContent = 'pending'

  const elapsed = document.createElement('span')
  elapsed.className = 'small'
  elapsed.textContent = '00:00:00'

  head.append(idSpan, badge, elapsed)

  const results = document.createElement('div')
  results.className = 'mb-3'

  const logButton = document.createElement('button')
  logButton.type = 'button'
  logButton.className = 'btn btn-sm btn-outline-secondary mb-2'
  logButton.textContent = 'Show log'

  const log = document.createElement('pre')
  log.className = 'small bg-light p-2 rounded'
  log.style.maxHeight = '300px'
  log.style.overflow = 'auto'
  log.hidden = true

  root.append(head, results, logButton, log)
  return { root, badge, elapsed, results, logButton, log }
}

function renderResults(container: HTMLDivElement, result: JobResult): void {
  container.replaceChildren()
  const heading = document.createElement('div')
  heading.className = 'small text-muted mb-2'
  heading.textContent = 'Results'
  container.appendChild(heading)

  const list = document.createElement('div')
  list.className = 'd-flex gap-2 flex-wrap'
  for (const [name, url] of Object.entries(result.urls)) {
    const a = document.createElement('a')
    a.className = 'btn btn-sm btn-primary'
    a.href = url
    a.download = ''
    a.textContent = name
    a.target = '_blank'
    a.rel = 'noopener noreferrer'
    list.appendChild(a)
  }
  container.appendChild(list)
}

function stop(inst: Instance): void {
  if (inst.pollHandle != null) {
    window.clearTimeout(inst.pollHandle)
    inst.pollHandle = null
  }
  if (inst.clockHandle != null) {
    window.clearInterval(inst.clockHandle)
    inst.clockHandle = null
  }
}

async function poll(inst: Instance): Promise<void> {
  try {
    const status: JobStatus = await getJobStatus(inst.jobId, inst.backend)
    inst.badge.className = badgeClass(status.status)
    inst.badge.textContent = status.status

    if (TERMINAL_STATUSES.has(status.status)) {
      stop(inst)
      if (status.status === 'finished' || status.status === 'completed' || status.status === 'success') {
        try {
          const result = await getJobResult(inst.jobId, inst.backend)
          renderResults(inst.resultsEl, result)
        } catch (err) {
          console.warn('Failed to fetch result:', err)
        }
      }
      return
    }
  } catch (err) {
    console.warn('Status poll failed:', err)
  }
  inst.pollHandle = window.setTimeout(() => poll(inst), POLL_INTERVAL_MS)
}

function attachLogButton(inst: Instance): void {
  inst.logButton.addEventListener('click', async () => {
    if (!inst.logEl.hidden) {
      inst.logEl.hidden = true
      inst.logButton.textContent = 'Show log'
      return
    }
    try {
      const text = await getJobLog(inst.jobId, inst.backend)
      inst.logEl.textContent = text
      inst.logEl.hidden = false
      inst.logButton.textContent = 'Hide log'
    } catch (err) {
      inst.logEl.textContent = 'Log not available yet.'
      inst.logEl.hidden = false
    }
  })
}

export const JobTracker = {
  init(container: HTMLElement, jobId: string, backend: string): void {
    const parts = build({ jobId, backend })
    container.replaceChildren(parts.root)

    const inst: Instance = {
      container,
      jobId,
      backend,
      startedAt: Date.now(),
      pollHandle: null,
      clockHandle: null,
      badge: parts.badge,
      elapsedEl: parts.elapsed,
      resultsEl: parts.results,
      logEl: parts.log,
      logButton: parts.logButton,
    }

    attachLogButton(inst)
    inst.clockHandle = window.setInterval(() => {
      inst.elapsedEl.textContent = formatElapsed(Date.now() - inst.startedAt)
    }, 1000)

    poll(inst)
  },
}
```

- [ ] **Step 2: Verify TypeScript compiles + build**

```bash
cd /Users/inutano/repos/chip-atlas && npx tsc --project frontend/tsconfig.json --noEmit && node esbuild.config.mjs
```

Expected: both exit 0.

- [ ] **Step 3: Commit**

Stage `frontend/components/job-tracker.ts`.

```
Add JobTracker shared component

Polls /jobs/:id/status every 10 seconds, shows status badge, live
elapsed clock, on-demand log viewer (/jobs/:id/log), and rendered
result download links (/jobs/:id/result). Stops polling on any
terminal status (finished/error/backend_unavailable). Designed for
Enrichment Analysis Result and Diff Analysis Result pages (Plan 3).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Final Verification

After all 7 tasks are complete, run:

```bash
cd /Users/inutano/repos/chip-atlas

# 1. TypeScript compiles cleanly across all components and pages
npx tsc --project frontend/tsconfig.json --noEmit && echo "TS: OK"

# 2. esbuild produces all expected bundles
node esbuild.config.mjs
test -f public/js/search.js     && echo "search.js: OK"
test -f public/js/experiment.js && echo "experiment.js: OK"
test -f public/js/homepage.js   && echo "homepage.js: OK"

# 3. All converted pages return 200, plus /view loads metadata
PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test \
ruby -e "
  require 'bundler/setup'
  require 'rack/test'
  require_relative 'app'
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  ['/', '/publications', '/agents', '/demo', '/search', '/view?id=SRX038634'].each do |path|
    get path
    puts \"#{path}: #{last_response.status}\"
  end
  get '/this-does-not-exist'
  puts \"404: #{last_response.status}\"
"

# 4. Backend tests still pass
bundle exec rake test 2>&1 | tail -10
```

Expected:
- `TS: OK`
- All three `*.js` files built
- `/`, `/publications`, `/agents`, `/demo`, `/search`, `/view?id=SRX038634` all return 200
- `404` returns 404
- 66 backend tests, 0 failures

The four shared components are not exercised by any page in Plan 2 (per design — Search and Experiment Detail don't use them). They will be exercised by Plan 3's analysis pages. The `tsc` clean compile + esbuild build success is the strongest signal we have at this stage.

---

## Dependencies Between Tasks

```
Task 1 (types)           — independent
Task 2 (Search page)     — depends on Task 1
Task 3 (Experiment page) — independent of Task 1 (uses ExperimentRecord, unchanged)
Task 4 (GenomeTabs)      — independent
Task 5 (Autocomplete)    — independent
Task 6 (FacetFilter)     — independent
Task 7 (JobTracker)      — independent
```

Tasks 4–7 (the components) can be implemented in any order. Task 2 must come after Task 1. The recommended order is sequential as written: types first, then user-facing pages (early validation), then components.
