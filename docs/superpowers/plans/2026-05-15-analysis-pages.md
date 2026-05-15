# Analysis Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the remaining nine analysis pages (target_genes setup + result, colo setup + result, enrichment_analysis result, diff_analysis result, peak_browser, enrichment_analysis, diff_analysis) from HAML + jQuery to ERB + TypeScript, consuming the four shared components shipped in Plan 2 (GenomeTabs, FacetFilter, Autocomplete, JobTracker). This is the final code-conversion plan in the frontend rebuild — after this every user-facing route is on the new stack.

**Architecture:** Each page route loads its server-side context (genome list, qval range, etc.) and embeds it as a JSON-island `<script type="application/json">` blob plus sets `@page_js` for the per-page bundle. The TypeScript module reads the JSON island, mounts the relevant shared components, wires form submission, and either navigates (Peak Browser, Target Genes setup, Colo setup) or POSTs to `/jobs/submit` then redirects to the result page (Enrichment Analysis, Diff Analysis). Result pages read `id` and `backend` from the URL and mount `JobTracker` (compute jobs) or fetch the analysis JSON and render tables (target genes, colo).

**Tech Stack:** TypeScript strict mode, esbuild, Bootstrap 5.3.3, ERB via erubi (escape_html honored), Sinatra, Sequel.

**Reference:** Frontend design spec at `docs/superpowers/specs/2026-05-12-frontend-rebuild-design.md`. Result JSON spec at `docs/result-json-spec.md`. Plan 1 + Plan 2 are complete — `frontend/api/client.ts` has typed wrappers for every endpoint, `frontend/components/` has the four shared components, `views/layout.erb` is the shared shell.

**Important notes:**
- Ruby is at `/opt/homebrew/opt/ruby/bin/ruby`. Prefix Ruby/bundle with `PATH="/opt/homebrew/opt/ruby/bin:$PATH"`.
- Tests must run with `RACK_ENV=test` to bypass the production host_authorization middleware.
- `escape_html: true` is now real (erubi shipped). Use `<%==` only for intentional raw-HTML emission (kramdown output, partial includes, JSON islands). Use `<%=` for everything else; auto-escape will protect against XSS in DB-derived data.
- esbuild auto-discovers `frontend/pages/*.ts`. New page files just need to exist — no esbuild config edit.
- All compiled `public/js/<page>.js` files are gitignored (per Plan 1's `.gitignore`).
- Test snippet pattern uses `%q(id="x")` for embedded double-quotes (Plan 2's lesson — single-quoted Ruby strings don't honor `\"` escapes).
- The legacy `views/*.haml` files are NOT deleted in this plan. A later cleanup task will remove them after this plan ships.
- The `FacetFilter` component (Plan 2) renders 5 selects: track_class, cell_type_class, track_subclass, cell_type_subclass, qval — with bidirectional counts on the class pair. Subclass-as-select is a minor UX regression from the legacy typeahead, accepted because it works; a future enhancement could swap the subclass selects for `Autocomplete` instances.
- The legacy enrichment_analysis page does live time-estimation by calling a backend endpoint. Plan 3 simplifies: estimated time is shown only after submission (via JobTracker on the result page), not during form input. This matches the diff_analysis flow which calls `POST /jobs/estimated_time` on textarea blur.

---

## File Structure (what this plan creates)

```
chip-atlas/
├── frontend/
│   ├── api/
│   │   └── client.ts                       # MODIFY: fix ColoIndex type
│   └── pages/
│       ├── target-genes.ts                 # NEW (Task 2)
│       ├── target-genes-result.ts          # NEW (Task 3)
│       ├── colo.ts                         # NEW (Task 4)
│       ├── colo-result.ts                  # NEW (Task 5)
│       ├── enrichment-result.ts            # NEW (Task 6)
│       ├── diff-result.ts                  # NEW (Task 7)
│       ├── peak-browser.ts                 # NEW (Task 8)
│       ├── enrichment-analysis.ts          # NEW (Task 9)
│       └── diff-analysis.ts                # NEW (Task 10)
├── views/
│   ├── target_genes.erb                    # NEW (Task 2)
│   ├── target_genes_result.erb             # NEW (Task 3)
│   ├── colo.erb                            # NEW (Task 4)
│   ├── colo_result.erb                     # NEW (Task 5)
│   ├── enrichment_analysis_result.erb      # NEW (Task 6)
│   ├── diff_analysis_result.erb            # NEW (Task 7)
│   ├── peak_browser.erb                    # NEW (Task 8)
│   ├── enrichment_analysis.erb             # NEW (Task 9)
│   └── diff_analysis.erb                   # NEW (Task 10)
├── routes/
│   └── pages.rb                            # MODIFY: each route sets @page_js, result routes accept ?id&backend
└── public/css/
    └── style.css                           # MODIFY: per-page rules where needed
```

---

### Task 1: Fix ColoIndex Type

**Files:**
- Modify: `frontend/api/client.ts`
- Test: `npx tsc --project frontend/tsconfig.json --noEmit`

The `/api/colo_index?genome=X` endpoint actually returns `{ <genome>: { track: { <track>: [<celltypes>] }, cell_type: { <celltype>: [<tracks>] } } }`. The current client interface declares `Record<string, string[]>` which is wrong on two counts: it doesn't model the genome wrapper, and it doesn't include the `cell_type` reverse mapping needed by Colo's "Cell Type → Antigen" search mode.

- [ ] **Step 1: Replace `ColoIndex` interface in `frontend/api/client.ts`**

Find:

```typescript
export interface ColoIndex {
  [track: string]: string[]  // track -> cell_types
}
```

Replace with:

```typescript
export interface ColoIndexEntry {
  track: Record<string, string[]>      // track -> cell_types
  cell_type: Record<string, string[]>  // cell_type -> tracks
}

export interface ColoIndex {
  [genome: string]: ColoIndexEntry
}
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd /Users/inutano/repos/chip-atlas && npx tsc --project frontend/tsconfig.json --noEmit
```

Expected: exit 0, no output.

- [ ] **Step 3: Commit**

Stage only `frontend/api/client.ts`. HEREDOC commit:

```
Fix ColoIndex type to model genome wrapper and cell_type reverse map

The /api/colo_index?genome=X endpoint returns
{ <genome>: { track: {...}, cell_type: {...} } }, not a flat
track-to-celltypes map. Plan 2 had it wrong; Colo setup needs the
cell_type direction for the "Cell Type -> Antigen" search mode.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 2: Target Genes Setup Page

**Files:**
- Create: `views/target_genes.erb`
- Create: `frontend/pages/target-genes.ts`
- Modify: `routes/pages.rb` (`/target_genes` route)
- Test: `GET /target_genes` returns 200 with expected DOM

The legacy `/target_genes` page has GenomeTabs, an Autocomplete for the antigen/track, radio buttons for distance from TSS (1k/5k/10k), and submit/download buttons. The route already loads `@list_of_genome` and `@index_all_genome` via `load_analysis_settings`, but we don't actually need either on this page — just the genome list. We'll use a JSON island for the genome list.

- [ ] **Step 1: Update `/target_genes` route**

Edit `/Users/inutano/repos/chip-atlas/routes/pages.rb`. Find:

```ruby
        app.get '/target_genes' do
          @index_all_genome = ChipAtlas::Experiment.cached_index_all_genome
          @list_of_genome   = ChipAtlas::Experiment.list_of_genome
          haml :target_genes
        end
```

Replace with:

```ruby
        app.get '/target_genes' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'target-genes'
          erb :target_genes
        end
```

(The `haml` call is replaced with `erb`. The `@index_all_genome` fetch is removed because this page only needs the genome list.)

- [ ] **Step 2: Create `views/target_genes.erb`**

Write to `/Users/inutano/repos/chip-atlas/views/target_genes.erb`:

```erb
<%
  @page_title = 'Target Genes'
  @page_description = 'Search for genes bound by given transcription factors.'
  @active_menu = 'target_genes'
%>
<script id="page-data" type="application/json"><%== { genomes: @list_of_genome }.to_json.gsub('</', '<\/') %></script>

<div class="row mb-3">
  <div class="col-md-12">
    <h1>ChIP-Atlas: Target Genes</h1>
    <p>Search for genes bound by given transcription factors.</p>
  </div>
</div>

<div id="genome-tabs"></div>

<div class="row">
  <div class="col-md-6">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">1. Choose Antigen</h5></div>
      <div class="card-body">
        <input type="text" id="track-input" class="form-control" placeholder="type to search" autocomplete="off">
      </div>
    </div>
  </div>
  <div class="col-md-6">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">2. Choose Distance from TSS</h5></div>
      <div class="card-body">
        <div class="form-check">
          <input class="form-check-input" type="radio" name="distance" id="distance-1" value="1" checked>
          <label class="form-check-label" for="distance-1">±1 kb</label>
        </div>
        <div class="form-check">
          <input class="form-check-input" type="radio" name="distance" id="distance-5" value="5">
          <label class="form-check-label" for="distance-5">±5 kb</label>
        </div>
        <div class="form-check">
          <input class="form-check-input" type="radio" name="distance" id="distance-10" value="10">
          <label class="form-check-label" for="distance-10">±10 kb</label>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="row mb-4">
  <div class="col-md-6 offset-md-3 d-grid gap-2">
    <button type="button" id="view-target-genes" class="btn btn-primary btn-lg">View Potential Target Genes</button>
    <button type="button" id="download-tsv" class="btn btn-outline-primary btn-lg">Download (TSV)</button>
  </div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/target-genes.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/pages/target-genes.ts`:

```typescript
// frontend/pages/target-genes.ts
// Target Genes setup: genome tabs + antigen autocomplete + distance radio + submit/download.

import { GenomeTabs } from '../components/genome-tabs'
import { Autocomplete } from '../components/autocomplete'
import { getTargetGenesIndex, type TargetGenesIndex } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

let currentGenome = ''
let currentTrack = ''
let allTracks: TargetGenesIndex = {}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function getDistance(): string {
  const checked = document.querySelector<HTMLInputElement>('input[name="distance"]:checked')
  return checked?.value || '1'
}

async function init(): Promise<void> {
  const data = readPageData()

  try {
    allTracks = await getTargetGenesIndex()
  } catch (err) {
    console.warn('Failed to load target genes index:', err)
  }

  const tabsContainer = $('genome-tabs')
  tabsContainer.addEventListener('genome-change', (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
    const tracks = allTracks[currentGenome] || []
    Autocomplete.setItems(trackInput, tracks)
    currentTrack = ''
    trackInput.value = ''
  })

  const trackInput = $('track-input') as HTMLInputElement
  Autocomplete.init(trackInput, [], (value) => {
    currentTrack = value
  })

  GenomeTabs.init(tabsContainer, data.genomes)

  $('view-target-genes').addEventListener('click', () => {
    if (!currentGenome || !currentTrack) {
      alert('Select a genome and antigen first.')
      return
    }
    const params = new URLSearchParams({ genome: currentGenome, track: currentTrack, distance: getDistance() })
    window.location.href = `/target_genes_result?${params.toString()}`
  })

  $('download-tsv').addEventListener('click', () => {
    if (!currentGenome || !currentTrack) {
      alert('Select a genome and antigen first.')
      return
    }
    const params = new URLSearchParams({
      genome: currentGenome, track: currentTrack, distance: getDistance(), format: 'tsv',
    })
    window.location.href = `/api/target_genes/download?${params.toString()}`
  })
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build the TypeScript**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/target-genes.js && echo "OK: target-genes.js built" || echo "FAIL"
```

- [ ] **Step 5: Test**

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/target_genes"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has page-data: #{body.include?(%q(id="page-data"))}"
  puts "Has genome-tabs: #{body.include?(%q(id="genome-tabs"))}"
  puts "Has track-input: #{body.include?(%q(id="track-input"))}"
  puts "Has distance radios: #{body.include?(%q(name="distance"))}"
  puts "Has submit button: #{body.include?(%q(id="view-target-genes"))}"
  puts "Has download button: #{body.include?(%q(id="download-tsv"))}"
  puts "Has page_js: #{body.include?("/js/target-genes.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 6: Commit**

Stage `routes/pages.rb`, `views/target_genes.erb`, `frontend/pages/target-genes.ts`. HEREDOC:

```
Convert /target_genes setup to ERB + TypeScript

Genome tabs (from JSON island), antigen Autocomplete (filled from
/api/target_genes_index per genome), distance radio (1/5/10 kb),
and submit + download buttons. Submit navigates to
/target_genes_result; Download triggers /api/target_genes/download
with the TSV format param.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 3: Target Genes Result Page

**Files:**
- Create: `views/target_genes_result.erb`
- Create: `frontend/pages/target-genes-result.ts`
- Modify: `routes/pages.rb` (`/target_genes_result` route)
- Test: `GET /target_genes_result?genome=hg38&track=CTCF&distance=5` returns 200 with skeleton; navigated load fetches API and renders

The legacy `/target_genes_result` route validated `params[:data_url]` pointing to a static HTML file. The new route accepts `genome`, `track`, `distance` and renders a thin skeleton; the TS fetches `/api/target_genes` and renders the gene × experiment matrix as an HTML table with gene-symbol search, column sort, and TSV download.

- [ ] **Step 1: Update `/target_genes_result` route**

Edit `/Users/inutano/repos/chip-atlas/routes/pages.rb`. Find:

```ruby
        app.get '/target_genes_result' do
          @data_url = params[:data_url]
          halt 400 unless @data_url&.start_with?('https://chip-atlas.dbcls.jp/')
          haml :target_genes_result
        end
```

Replace with:

```ruby
        app.get '/target_genes_result' do
          @page_js = 'target-genes-result'
          erb :target_genes_result
        end
```

- [ ] **Step 2: Create `views/target_genes_result.erb`**

```erb
<%
  @page_title = 'Target Genes Result'
  @page_description = 'Predicted target genes ranked by peak score.'
  @active_menu = 'target_genes'
%>
<div class="row mb-3">
  <div class="col-md-12">
    <h1>ChIP-Atlas: Target Genes Result</h1>
    <div id="result-summary" class="text-muted small"></div>
  </div>
</div>

<div id="loading-state" class="text-muted">Loading…</div>
<div id="error-state" class="alert alert-danger" hidden></div>

<div id="result-wrap" hidden>
  <div class="row mb-2">
    <div class="col-md-6">
      <input type="search" id="gene-search" class="form-control form-control-sm" placeholder="Filter by gene symbol" aria-label="Filter genes">
    </div>
    <div class="col-md-6 text-end">
      <button type="button" id="download-tsv" class="btn btn-sm btn-outline-secondary">Download TSV</button>
    </div>
  </div>
  <div class="table-responsive">
    <table class="table table-striped table-sm">
      <thead id="result-thead"></thead>
      <tbody id="result-tbody"></tbody>
    </table>
  </div>
  <div id="row-count" class="text-muted small mt-2"></div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/target-genes-result.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/pages/target-genes-result.ts`:

```typescript
// frontend/pages/target-genes-result.ts
// Fetches /api/target_genes and renders the gene x experiment score matrix.

import { getTargetGenesData } from '../api/client'

interface ExperimentRow {
  experiment_id: string
  cell_type: string
  cell_type_class: string
}

interface GeneRow {
  symbol: string
  avg_score: number
  scores: number[]
}

interface ResultData {
  genome: string
  track: string
  distance: string
  experiments: ExperimentRow[]
  genes: GeneRow[]
}

interface State {
  data: ResultData | null
  filter: string
  sortColumn: number  // -1 = avg, 0..N = experiment index
  sortDescending: boolean
}

const state: State = { data: null, filter: '', sortColumn: -1, sortDescending: true }

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readQueryParams(): { genome: string; track: string; distance: string } | null {
  const p = new URLSearchParams(window.location.search)
  const genome = p.get('genome')
  const track = p.get('track')
  const distance = p.get('distance')
  if (!genome || !track || !distance) return null
  return { genome, track, distance }
}

function renderHeader(data: ResultData): void {
  const thead = $('result-thead')
  const tr = document.createElement('tr')

  const symbolTh = document.createElement('th')
  symbolTh.scope = 'col'
  symbolTh.textContent = 'Gene'
  tr.appendChild(symbolTh)

  const avgTh = document.createElement('th')
  avgTh.scope = 'col'
  avgTh.style.cursor = 'pointer'
  avgTh.textContent = `Avg ${state.sortColumn === -1 ? (state.sortDescending ? '↓' : '↑') : ''}`
  avgTh.addEventListener('click', () => toggleSort(-1))
  tr.appendChild(avgTh)

  data.experiments.forEach((exp, i) => {
    const th = document.createElement('th')
    th.scope = 'col'
    th.style.cursor = 'pointer'
    th.title = `${exp.cell_type} (${exp.cell_type_class})`
    th.textContent = `${exp.experiment_id} ${state.sortColumn === i ? (state.sortDescending ? '↓' : '↑') : ''}`
    th.addEventListener('click', () => toggleSort(i))
    tr.appendChild(th)
  })

  thead.replaceChildren(tr)
}

function toggleSort(column: number): void {
  if (state.sortColumn === column) {
    state.sortDescending = !state.sortDescending
  } else {
    state.sortColumn = column
    state.sortDescending = true
  }
  if (state.data) renderRows(state.data)
  if (state.data) renderHeader(state.data)
}

function renderRows(data: ResultData): void {
  const filter = state.filter.toLowerCase()
  const filtered = filter
    ? data.genes.filter((g) => g.symbol.toLowerCase().includes(filter))
    : data.genes.slice()

  const sorted = filtered.sort((a, b) => {
    const av = state.sortColumn === -1 ? a.avg_score : (a.scores[state.sortColumn] ?? 0)
    const bv = state.sortColumn === -1 ? b.avg_score : (b.scores[state.sortColumn] ?? 0)
    return state.sortDescending ? bv - av : av - bv
  })

  const tbody = $('result-tbody')
  tbody.replaceChildren(...sorted.map((g) => {
    const tr = document.createElement('tr')

    const symbolTd = document.createElement('td')
    symbolTd.textContent = g.symbol
    tr.appendChild(symbolTd)

    const avgTd = document.createElement('td')
    avgTd.textContent = g.avg_score.toFixed(2)
    tr.appendChild(avgTd)

    g.scores.forEach((s) => {
      const td = document.createElement('td')
      td.textContent = s.toFixed(2)
      tr.appendChild(td)
    })
    return tr
  }))

  $('row-count').textContent = `${sorted.length.toLocaleString()} genes shown (of ${data.genes.length.toLocaleString()} total)`
}

function downloadTsv(): void {
  const params = readQueryParams()
  if (!params) return
  const url = `/api/target_genes/download?${new URLSearchParams({ ...params, format: 'tsv' }).toString()}`
  window.location.href = url
}

async function init(): Promise<void> {
  const params = readQueryParams()
  if (!params) {
    ;($('loading-state') as HTMLElement).hidden = true
    const err = $('error-state') as HTMLElement
    err.textContent = 'Missing genome, track, or distance parameter in URL.'
    err.hidden = false
    return
  }

  $('result-summary').textContent = `${params.track} on ${params.genome} (TSS ± ${params.distance} kb)`

  try {
    const data = await getTargetGenesData(params.genome, params.track, params.distance) as unknown as ResultData
    state.data = data
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = false
    renderHeader(data)
    renderRows(data)
  } catch (err) {
    console.error(err)
    ;($('loading-state') as HTMLElement).hidden = true
    const e = $('error-state') as HTMLElement
    e.textContent = 'Failed to load results. The data may not exist yet for this combination.'
    e.hidden = false
    return
  }

  ;($('gene-search') as HTMLInputElement).addEventListener('input', (e) => {
    state.filter = (e.target as HTMLInputElement).value
    if (state.data) renderRows(state.data)
  })

  $('download-tsv').addEventListener('click', downloadTsv)
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/target-genes-result.js && echo "OK"
```

- [ ] **Step 5: Test the route renders**

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/target_genes_result?genome=hg38&track=CTCF&distance=5"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has loading state: #{body.include?(%q(id="loading-state"))}"
  puts "Has result wrap: #{body.include?(%q(id="result-wrap"))}"
  puts "Has gene search: #{body.include?(%q(id="gene-search"))}"
  puts "Has page_js: #{body.include?("/js/target-genes-result.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 6: Commit**

Stage `routes/pages.rb`, `views/target_genes_result.erb`, `frontend/pages/target-genes-result.ts`. HEREDOC:

```
Convert /target_genes_result to ERB + TypeScript

Reads genome/track/distance from URL query params, fetches
/api/target_genes, renders the gene x experiment score matrix as an
HTML table. Supports gene-symbol filter, click-to-sort by avg or any
experiment column, and TSV download via the API endpoint. The legacy
data_url-based route (which pointed at a static HTML file) is
replaced — the new flow consumes the JSON spec from the pipeline v2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 4: Colocalization Setup Page

**Files:**
- Create: `views/colo.erb`
- Create: `frontend/pages/colo.ts`
- Modify: `routes/pages.rb` (`/colo` route)
- Test: `GET /colo` returns 200 with expected DOM

The legacy `/colo` page has GenomeTabs, a search-direction radio (Antigen→Cell Type vs Cell Type→Antigen), Autocomplete inputs for primary and secondary type, and submit + TSV/GML download buttons. The TS uses `/api/colo_index?genome=X` to populate the autocomplete pools.

- [ ] **Step 1: Update `/colo` route**

Edit `/Users/inutano/repos/chip-atlas/routes/pages.rb`. Find:

```ruby
        app.get '/colo' do
          @index_all_genome = ChipAtlas::Experiment.cached_index_all_genome
          @list_of_genome   = ChipAtlas::Experiment.list_of_genome
          haml :colo
        end
```

Replace with:

```ruby
        app.get '/colo' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'colo'
          erb :colo
        end
```

- [ ] **Step 2: Create `views/colo.erb`**

```erb
<%
  @page_title = 'Colocalization'
  @page_description = 'Predict potential partner proteins that form complexes with given TFs.'
  @active_menu = 'colo'
%>
<script id="page-data" type="application/json"><%== { genomes: @list_of_genome }.to_json.gsub('</', '<\/') %></script>

<div class="row mb-3">
  <div class="col-md-12">
    <h1>ChIP-Atlas: Colocalization</h1>
    <p>Predict potential partner proteins that form complexes with given TFs.</p>
  </div>
</div>

<div id="genome-tabs"></div>

<div class="row">
  <div class="col-md-4">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">1. Search mode</h5></div>
      <div class="card-body">
        <div class="form-check">
          <input class="form-check-input" type="radio" name="direction" id="direction-track" value="track" checked>
          <label class="form-check-label" for="direction-track">Antigens → Cell Type</label>
        </div>
        <div class="form-check">
          <input class="form-check-input" type="radio" name="direction" id="direction-cell" value="cell_type">
          <label class="form-check-label" for="direction-cell">Cell Type → Antigen</label>
        </div>
      </div>
    </div>
  </div>
  <div class="col-md-4">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">2. Choose Primary Type</h5></div>
      <div class="card-body">
        <input type="text" id="primary-input" class="form-control" placeholder="type to search" autocomplete="off">
      </div>
    </div>
  </div>
  <div class="col-md-4">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">3. Choose Secondary Type</h5></div>
      <div class="card-body">
        <input type="text" id="secondary-input" class="form-control" placeholder="type to search" autocomplete="off">
      </div>
    </div>
  </div>
</div>

<div class="row mb-2">
  <div class="col-md-6 offset-md-3 d-grid">
    <button type="button" id="view-colo" class="btn btn-primary btn-lg">View Colocalization Data</button>
  </div>
</div>

<div class="row mb-4">
  <div class="col-md-3 offset-md-3 d-grid">
    <button type="button" id="download-tsv" class="btn btn-outline-primary">Download (TSV)</button>
  </div>
  <div class="col-md-3 d-grid">
    <button type="button" id="download-gml" class="btn btn-outline-primary">Download (GML)</button>
  </div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/colo.ts`**

Write to `/Users/inutano/repos/chip-atlas/frontend/pages/colo.ts`:

```typescript
// frontend/pages/colo.ts
// Colocalization setup: genome tabs + direction radio + primary/secondary autocomplete + submit/download.

import { GenomeTabs } from '../components/genome-tabs'
import { Autocomplete } from '../components/autocomplete'
import { getColoIndex, type ColoIndex } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

let currentGenome = ''
let currentPrimary = ''
let currentSecondary = ''
const coloIndex: ColoIndex = {}

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function getDirection(): 'track' | 'cell_type' {
  const r = document.querySelector<HTMLInputElement>('input[name="direction"]:checked')
  return r?.value === 'cell_type' ? 'cell_type' : 'track'
}

async function loadGenomeIndex(genome: string): Promise<void> {
  if (coloIndex[genome]) return
  try {
    const data = await getColoIndex(genome)
    coloIndex[genome] = data[genome]
  } catch (err) {
    console.warn('Failed to load colo index for', genome, err)
  }
}

function buildLinkParams(): URLSearchParams | null {
  if (!currentGenome || !currentPrimary || !currentSecondary) return null
  const direction = getDirection()
  const track = direction === 'track' ? currentPrimary : currentSecondary
  const cellType = direction === 'track' ? currentSecondary : currentPrimary
  return new URLSearchParams({ genome: currentGenome, track, cell_type: cellType })
}

async function init(): Promise<void> {
  const data = readPageData()
  const pInput = $('primary-input') as HTMLInputElement
  const sInput = $('secondary-input') as HTMLInputElement

  function refresh(): void {
    const entry = coloIndex[currentGenome]
    if (!entry) {
      Autocomplete.setItems(pInput, [])
      Autocomplete.setItems(sInput, [])
      return
    }
    const direction = getDirection()
    if (direction === 'track') {
      Autocomplete.setItems(pInput, Object.keys(entry.track))
      const secondaries = currentPrimary && entry.track[currentPrimary]
        ? entry.track[currentPrimary]
        : Object.keys(entry.cell_type)
      Autocomplete.setItems(sInput, secondaries)
    } else {
      Autocomplete.setItems(pInput, Object.keys(entry.cell_type))
      const secondaries = currentPrimary && entry.cell_type[currentPrimary]
        ? entry.cell_type[currentPrimary]
        : Object.keys(entry.track)
      Autocomplete.setItems(sInput, secondaries)
    }
  }

  Autocomplete.init(pInput, [], (value) => {
    currentPrimary = value
    refresh()
  })
  Autocomplete.init(sInput, [], (value) => {
    currentSecondary = value
  })

  document.querySelectorAll<HTMLInputElement>('input[name="direction"]').forEach((r) => {
    r.addEventListener('change', () => {
      currentPrimary = ''
      currentSecondary = ''
      pInput.value = ''
      sInput.value = ''
      refresh()
    })
  })

  const tabs = $('genome-tabs')
  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
    currentPrimary = ''
    currentSecondary = ''
    pInput.value = ''
    sInput.value = ''
    await loadGenomeIndex(currentGenome)
    refresh()
  })

  GenomeTabs.init(tabs, data.genomes)

  $('view-colo').addEventListener('click', () => {
    const params = buildLinkParams()
    if (!params) { alert('Select a primary and secondary type first.'); return }
    window.location.href = `/colo_result?${params.toString()}`
  })

  $('download-tsv').addEventListener('click', () => {
    const params = buildLinkParams()
    if (!params) { alert('Select a primary and secondary type first.'); return }
    params.set('format', 'tsv')
    window.location.href = `/api/colo/download?${params.toString()}`
  })

  $('download-gml').addEventListener('click', () => {
    const params = buildLinkParams()
    if (!params) { alert('Select a primary and secondary type first.'); return }
    params.set('format', 'gml')
    window.location.href = `/api/colo/download?${params.toString()}`
  })
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/colo.js && echo "OK"
```

- [ ] **Step 5: Test**

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/colo"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has page-data: #{body.include?(%q(id="page-data"))}"
  puts "Has direction radios: #{body.include?(%q(name="direction"))}"
  puts "Has primary input: #{body.include?(%q(id="primary-input"))}"
  puts "Has secondary input: #{body.include?(%q(id="secondary-input"))}"
  puts "Has view button: #{body.include?(%q(id="view-colo"))}"
  puts "Has tsv button: #{body.include?(%q(id="download-tsv"))}"
  puts "Has gml button: #{body.include?(%q(id="download-gml"))}"
  puts "Has page_js: #{body.include?("/js/colo.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 6: Commit**

Stage `routes/pages.rb`, `views/colo.erb`, `frontend/pages/colo.ts`. HEREDOC:

```
Convert /colo setup to ERB + TypeScript

Genome tabs (from JSON island), direction radio (track-> cell_type
or cell_type -> track), primary/secondary Autocomplete inputs filled
from /api/colo_index, and submit + TSV/GML download buttons. The
secondary list is filtered by the primary's available partners
(track[primary] or cell_type[primary]) so users only see valid
combinations.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 5: Colocalization Result Page

**Files:**
- Create: `views/colo_result.erb`
- Create: `frontend/pages/colo-result.ts`
- Modify: `routes/pages.rb` (`/colo_result` route)
- Test: `GET /colo_result?genome=hg38&track=CTCF&cell_type=Neural` returns 200

- [ ] **Step 1: Update `/colo_result` route**

Find:

```ruby
        app.get '/colo_result' do
          @data_url = params[:data_url]
          halt 400 unless @data_url&.start_with?('https://chip-atlas.dbcls.jp/')
          haml :colo_result
        end
```

Replace:

```ruby
        app.get '/colo_result' do
          @page_js = 'colo-result'
          erb :colo_result
        end
```

- [ ] **Step 2: Create `views/colo_result.erb`**

```erb
<%
  @page_title = 'Colocalization Result'
  @page_description = 'Predicted colocalization partners ranked by score.'
  @active_menu = 'colo'
%>
<div class="row mb-3">
  <div class="col-md-12">
    <h1>ChIP-Atlas: Colocalization Result</h1>
    <div id="result-summary" class="text-muted small"></div>
  </div>
</div>

<div id="loading-state" class="text-muted">Loading…</div>
<div id="error-state" class="alert alert-danger" hidden></div>

<div id="result-wrap" hidden>
  <div class="row mb-2">
    <div class="col-md-6">
      <input type="search" id="partner-search" class="form-control form-control-sm" placeholder="Filter by track or cell type" aria-label="Filter partners">
    </div>
    <div class="col-md-6 text-end">
      <button type="button" id="download-tsv" class="btn btn-sm btn-outline-secondary">Download TSV</button>
      <button type="button" id="download-gml" class="btn btn-sm btn-outline-secondary">Download GML</button>
    </div>
  </div>
  <div class="table-responsive">
    <table class="table table-striped table-sm">
      <thead>
        <tr>
          <th scope="col">Rank</th>
          <th scope="col">Track</th>
          <th scope="col">Cell Type</th>
          <th scope="col">Cell Type Class</th>
          <th scope="col">Score</th>
          <th scope="col">Shared Bins</th>
          <th scope="col">Experiment ID</th>
        </tr>
      </thead>
      <tbody id="result-tbody"></tbody>
    </table>
  </div>
  <div id="row-count" class="text-muted small mt-2"></div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/colo-result.ts`**

```typescript
// frontend/pages/colo-result.ts
// Fetches /api/colo and renders the colocalization partners table.

import { getColoData } from '../api/client'

interface Partner {
  experiment_id: string
  track: string
  cell_type: string
  cell_type_class: string
  score: number
  shared_bins: number
}

interface ResultData {
  genome: string
  track: string
  cell_type: string
  partners: Partner[]
}

interface State {
  data: ResultData | null
  filter: string
}

const state: State = { data: null, filter: '' }

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readQueryParams(): { genome: string; track: string; cell_type: string } | null {
  const p = new URLSearchParams(window.location.search)
  const genome = p.get('genome')
  const track = p.get('track')
  const cell_type = p.get('cell_type')
  if (!genome || !track || !cell_type) return null
  return { genome, track, cell_type }
}

function renderRows(data: ResultData): void {
  const filter = state.filter.toLowerCase()
  const filtered = filter
    ? data.partners.filter((p) =>
        p.track.toLowerCase().includes(filter) || p.cell_type.toLowerCase().includes(filter))
    : data.partners

  const tbody = $('result-tbody')
  tbody.replaceChildren(...filtered.map((p, i) => {
    const tr = document.createElement('tr')

    const rankTd = document.createElement('td')
    rankTd.textContent = String(i + 1)
    tr.appendChild(rankTd)

    const trackTd = document.createElement('td')
    trackTd.textContent = p.track
    tr.appendChild(trackTd)

    const cellTd = document.createElement('td')
    cellTd.textContent = p.cell_type
    tr.appendChild(cellTd)

    const classTd = document.createElement('td')
    classTd.textContent = p.cell_type_class
    tr.appendChild(classTd)

    const scoreTd = document.createElement('td')
    scoreTd.textContent = p.score.toFixed(2)
    tr.appendChild(scoreTd)

    const binsTd = document.createElement('td')
    binsTd.textContent = p.shared_bins.toLocaleString()
    tr.appendChild(binsTd)

    const expTd = document.createElement('td')
    const link = document.createElement('a')
    link.href = `/view?id=${encodeURIComponent(p.experiment_id)}`
    link.textContent = p.experiment_id
    expTd.appendChild(link)
    tr.appendChild(expTd)

    return tr
  }))

  $('row-count').textContent = `${filtered.length.toLocaleString()} partners shown (of ${data.partners.length.toLocaleString()} total)`
}

function downloadFile(format: 'tsv' | 'gml'): void {
  const params = readQueryParams()
  if (!params) return
  const search = new URLSearchParams({ ...params, format })
  window.location.href = `/api/colo/download?${search.toString()}`
}

async function init(): Promise<void> {
  const params = readQueryParams()
  if (!params) {
    ;($('loading-state') as HTMLElement).hidden = true
    const e = $('error-state') as HTMLElement
    e.textContent = 'Missing genome, track, or cell_type parameter in URL.'
    e.hidden = false
    return
  }

  $('result-summary').textContent = `${params.track} (${params.cell_type}) on ${params.genome}`

  try {
    const data = await getColoData(params.genome, params.track, params.cell_type) as unknown as ResultData
    state.data = data
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = false
    renderRows(data)
  } catch (err) {
    console.error(err)
    ;($('loading-state') as HTMLElement).hidden = true
    const e = $('error-state') as HTMLElement
    e.textContent = 'Failed to load colocalization data.'
    e.hidden = false
    return
  }

  ;($('partner-search') as HTMLInputElement).addEventListener('input', (e) => {
    state.filter = (e.target as HTMLInputElement).value
    if (state.data) renderRows(state.data)
  })

  $('download-tsv').addEventListener('click', () => downloadFile('tsv'))
  $('download-gml').addEventListener('click', () => downloadFile('gml'))
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build + Test**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/colo-result.js && echo "BUILD_OK"

PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/colo_result?genome=hg38&track=CTCF&cell_type=Neural"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has loading: #{body.include?(%q(id="loading-state"))}"
  puts "Has tbody: #{body.include?(%q(id="result-tbody"))}"
  puts "Has gml button: #{body.include?(%q(id="download-gml"))}"
  puts "Has page_js: #{body.include?("/js/colo-result.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 5: Commit**

Stage `routes/pages.rb`, `views/colo_result.erb`, `frontend/pages/colo-result.ts`. HEREDOC:

```
Convert /colo_result to ERB + TypeScript

Reads genome/track/cell_type from URL query params, fetches /api/colo,
renders the partners table sorted by score (server-pre-sorted).
Filters by track or cell_type substring; experiment_id links to
/view; TSV and GML downloads via the API endpoint. Replaces the
legacy data_url-based route that pointed at static HTML.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 6: Enrichment Analysis Result Page

**Files:**
- Create: `views/enrichment_analysis_result.erb`
- Create: `frontend/pages/enrichment-result.ts`
- Modify: `routes/pages.rb` (`/enrichment_analysis_result` route)
- Test: `GET /enrichment_analysis_result?id=abc123&backend=wabi` returns 200

- [ ] **Step 1: Update `/enrichment_analysis_result` route**

Find:

```ruby
        app.get '/enrichment_analysis_result' do
          haml :enrichment_analysis_result
        end
```

Replace:

```ruby
        app.get '/enrichment_analysis_result' do
          @page_js = 'enrichment-result'
          erb :enrichment_analysis_result
        end
```

- [ ] **Step 2: Create `views/enrichment_analysis_result.erb`**

```erb
<%
  @page_title = 'Enrichment Analysis Result'
  @page_description = 'Job status and downloads for a submitted enrichment analysis.'
  @active_menu = 'enrichment_analysis'
%>
<div class="row mb-3">
  <div class="col-md-10 offset-md-1">
    <h1>ChIP-Atlas: Enrichment Analysis Result</h1>
  </div>
</div>

<div class="row">
  <div class="col-md-10 offset-md-1">
    <div id="job-tracker"></div>
    <div id="error-state" class="alert alert-danger" hidden></div>
  </div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/enrichment-result.ts`**

```typescript
// frontend/pages/enrichment-result.ts
// Mounts JobTracker for an enrichment analysis job.

import { JobTracker } from '../components/job-tracker'

function init(): void {
  const params = new URLSearchParams(window.location.search)
  const id = params.get('id')
  const backend = params.get('backend')

  if (!id || !backend) {
    const err = document.getElementById('error-state')
    if (err) {
      err.textContent = 'Missing id or backend parameter in URL.'
      err.hidden = false
    }
    return
  }

  const container = document.getElementById('job-tracker')
  if (!container) return
  JobTracker.init(container, id, backend)
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build + Test**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/enrichment-result.js && echo "BUILD_OK"

PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/enrichment_analysis_result?id=abc123&backend=wabi"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has tracker container: #{body.include?(%q(id="job-tracker"))}"
  puts "Has page_js: #{body.include?("/js/enrichment-result.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 5: Commit**

Stage `routes/pages.rb`, `views/enrichment_analysis_result.erb`, `frontend/pages/enrichment-result.ts`. HEREDOC:

```
Convert /enrichment_analysis_result to ERB + JobTracker

Thin ERB skeleton + 20-line TS that reads ?id and ?backend from the
URL and mounts the JobTracker shared component (Plan 2). All polling,
status badge, elapsed clock, log viewer, and result-download wiring
lives in JobTracker.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 7: Diff Analysis Result Page

**Files:**
- Create: `views/diff_analysis_result.erb`
- Create: `frontend/pages/diff-result.ts`
- Modify: `routes/pages.rb` (`/diff_analysis_result` route)
- Test: `GET /diff_analysis_result?id=abc123&backend=wabi` returns 200

- [ ] **Step 1: Update `/diff_analysis_result` route**

Find:

```ruby
        app.get '/diff_analysis_result' do
          haml :diff_analysis_result
        end
```

Replace:

```ruby
        app.get '/diff_analysis_result' do
          @page_js = 'diff-result'
          erb :diff_analysis_result
        end
```

- [ ] **Step 2: Create `views/diff_analysis_result.erb`**

```erb
<%
  @page_title = 'Diff Analysis Result'
  @page_description = 'Job status and downloads for a submitted diff analysis.'
  @active_menu = 'diff_analysis'
%>
<div class="row mb-3">
  <div class="col-md-10 offset-md-1">
    <h1>ChIP-Atlas: Diff Analysis Result</h1>
  </div>
</div>

<div class="row">
  <div class="col-md-10 offset-md-1">
    <div id="job-tracker"></div>
    <div id="error-state" class="alert alert-danger" hidden></div>
  </div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/diff-result.ts`**

```typescript
// frontend/pages/diff-result.ts
// Mounts JobTracker for a diff analysis job.

import { JobTracker } from '../components/job-tracker'

function init(): void {
  const params = new URLSearchParams(window.location.search)
  const id = params.get('id')
  const backend = params.get('backend')

  if (!id || !backend) {
    const err = document.getElementById('error-state')
    if (err) {
      err.textContent = 'Missing id or backend parameter in URL.'
      err.hidden = false
    }
    return
  }

  const container = document.getElementById('job-tracker')
  if (!container) return
  JobTracker.init(container, id, backend)
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build + Test**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/diff-result.js && echo "BUILD_OK"

PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/diff_analysis_result?id=abc123&backend=wabi"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has tracker container: #{body.include?(%q(id="job-tracker"))}"
  puts "Has page_js: #{body.include?("/js/diff-result.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 5: Commit**

Stage `routes/pages.rb`, `views/diff_analysis_result.erb`, `frontend/pages/diff-result.ts`. HEREDOC:

```
Convert /diff_analysis_result to ERB + JobTracker

Same shape as enrichment-result: reads ?id and ?backend, mounts
JobTracker (Plan 2). Kept as a separate per-page module so each
analysis type can later add its own pre/post hooks if needed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 8: Peak Browser Page

**Files:**
- Create: `views/peak_browser.erb`
- Create: `frontend/pages/peak-browser.ts`
- Modify: `routes/pages.rb` (`/peak_browser` route)
- Test: `GET /peak_browser` returns 200

The flagship page. Genome tabs at top, FacetFilter (5 cascading selects with bidirectional counts), and IGV / Download buttons that POST to `/api/igv_url` and `/api/download_url` with the FacetFilter condition.

- [ ] **Step 1: Update `/peak_browser` route**

Find:

```ruby
        app.get '/peak_browser' do
          load_analysis_settings
          haml :peak_browser
        end
```

Replace:

```ruby
        app.get '/peak_browser' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'peak-browser'
          erb :peak_browser
        end
```

(`load_analysis_settings` loaded data the new flow doesn't need server-side — FacetFilter fetches its own data from the API at component init.)

- [ ] **Step 2: Create `views/peak_browser.erb`**

```erb
<%
  @page_title = 'Peak Browser'
  @page_description = 'Visualize all peaks of the public ChIP-Seq data on IGV.'
  @active_menu = 'peak_browser'
%>
<script id="page-data" type="application/json"><%== { genomes: @list_of_genome }.to_json.gsub('</', '<\/') %></script>

<div class="row mb-3">
  <div class="col-md-12">
    <h1>ChIP-Atlas: Peak Browser</h1>
    <p>Visualize TF-binding, histone marks, chromatin accessibility, and DNA methylation on
      <a href="http://software.broadinstitute.org/software/igv/home" target="_blank" rel="noopener noreferrer">IGV</a>.
    </p>
  </div>
</div>

<div id="genome-tabs"></div>

<div class="row">
  <div class="col-md-9">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">Filter</h5></div>
      <div class="card-body">
        <div id="facet-filter"></div>
      </div>
    </div>
  </div>
  <div class="col-md-3">
    <div class="d-grid gap-2">
      <button type="button" id="view-igv" class="btn btn-primary btn-lg">View on IGV</button>
      <button type="button" id="download-bed" class="btn btn-outline-primary btn-lg">Download BED</button>
    </div>
    <div id="action-status" class="text-muted small mt-2" aria-live="polite"></div>
  </div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/peak-browser.ts`**

```typescript
// frontend/pages/peak-browser.ts
// Genome tabs + FacetFilter + IGV/Download actions.

import { GenomeTabs } from '../components/genome-tabs'
import { FacetFilter } from '../components/facet-filter'
import { getIgvUrl, getDownloadUrl, type UrlCondition } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function buildCondition(facet: HTMLElement): UrlCondition | null {
  const c = FacetFilter.getCondition(facet)
  if (!c) return null
  return {
    genome: c.genome,
    track_class: c.track_class,
    track_subclass: c.track_subclass || undefined,
    cell_type_class: c.cell_type_class || undefined,
    cell_type_subclass: c.cell_type_subclass || undefined,
    qval: c.qval || undefined,
  }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const facet = $('facet-filter')
  const status = $('action-status')

  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    if (FacetFilter.getCondition(facet)) {
      await FacetFilter.setGenome(facet, detail.genome)
    } else {
      await FacetFilter.init(facet, detail.genome)
    }
  })

  GenomeTabs.init(tabs, data.genomes)

  $('view-igv').addEventListener('click', async () => {
    const condition = buildCondition(facet)
    if (!condition) { status.textContent = 'Select a track type first.'; return }
    status.textContent = 'Building IGV link…'
    try {
      const res = await getIgvUrl(condition)
      status.textContent = ''
      window.location.href = res.url
    } catch (err) {
      console.error(err)
      status.textContent = 'Failed to build IGV link.'
    }
  })

  $('download-bed').addEventListener('click', async () => {
    const condition = buildCondition(facet)
    if (!condition) { status.textContent = 'Select a track type first.'; return }
    status.textContent = 'Building download link…'
    try {
      const res = await getDownloadUrl(condition)
      status.textContent = ''
      window.location.href = res.url
    } catch (err) {
      console.error(err)
      status.textContent = 'Failed to build download link.'
    }
  })
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build + Test**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/peak-browser.js && echo "BUILD_OK"

PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/peak_browser"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has page-data: #{body.include?(%q(id="page-data"))}"
  puts "Has genome-tabs: #{body.include?(%q(id="genome-tabs"))}"
  puts "Has facet-filter: #{body.include?(%q(id="facet-filter"))}"
  puts "Has IGV button: #{body.include?(%q(id="view-igv"))}"
  puts "Has download button: #{body.include?(%q(id="download-bed"))}"
  puts "Has page_js: #{body.include?("/js/peak-browser.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 5: Commit**

Stage `routes/pages.rb`, `views/peak_browser.erb`, `frontend/pages/peak-browser.ts`. HEREDOC:

```
Convert /peak_browser to ERB + GenomeTabs + FacetFilter

The flagship page is now ~70 lines of TS instead of 443 lines of
jQuery. GenomeTabs at top, FacetFilter (5 cascading selects with
bidirectional counts), and View on IGV / Download BED buttons that
POST to /api/igv_url and /api/download_url respectively. The route
no longer eager-loads the index — FacetFilter fetches what it needs
from the classification API endpoints.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 9: Enrichment Analysis Page

**Files:**
- Create: `views/enrichment_analysis.erb`
- Create: `frontend/pages/enrichment-analysis.ts`
- Modify: `routes/pages.rb` (`/enrichment_analysis` GET + POST routes)
- Test: `GET /enrichment_analysis` returns 200

The most complex form in the app. Has GenomeTabs + FacetFilter + two large datasets (BED / Gene list / Count table) with file upload, plus a "compared with" panel with multiple options. The legacy POST route accepted `taxonomy/genes/genesetA/genesetB` to pre-fill the form when navigated to from elsewhere — we keep that.

- [ ] **Step 1: Update `/enrichment_analysis` GET and POST routes**

Find:

```ruby
        app.get '/enrichment_analysis' do
          load_analysis_settings
          haml :enrichment_analysis
        end

        app.post '/enrichment_analysis' do
          @taxonomy  = params['taxonomy']
          @genes     = params['genes']
          @genesetA  = params['genesetA']
          @genesetB  = params['genesetB']
          log_activity('enrichment_analysis', { taxonomy: @taxonomy })
          load_analysis_settings
          haml :enrichment_analysis
        end
```

Replace with:

```ruby
        app.get '/enrichment_analysis' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'enrichment-analysis'
          erb :enrichment_analysis
        end

        app.post '/enrichment_analysis' do
          @taxonomy  = params['taxonomy']
          @genes     = params['genes']
          @genesetA  = params['genesetA']
          @genesetB  = params['genesetB']
          log_activity('enrichment_analysis', { taxonomy: @taxonomy })
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'enrichment-analysis'
          erb :enrichment_analysis
        end
```

- [ ] **Step 2: Create `views/enrichment_analysis.erb`**

Write:

```erb
<%
  @page_title = 'Enrichment Analysis'
  @page_description = 'Identify common epigenetic features of a given set of genomic loci and genes.'
  @active_menu = 'enrichment_analysis'
%>
<script id="page-data" type="application/json"><%== {
  genomes: @list_of_genome,
  prefill: {
    taxonomy: @taxonomy,
    genes: @genes,
    genesetA: @genesetA,
    genesetB: @genesetB,
  }
}.to_json.gsub('</', '<\/') %></script>

<div class="row mb-3">
  <div class="col-md-12">
    <h1>ChIP-Atlas: Enrichment Analysis</h1>
    <p>Identify common epigenetic features of a given set of genomic loci and genes.</p>
  </div>
</div>

<div id="genome-tabs"></div>

<div class="row">
  <div class="col-md-6">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">1. Filter</h5></div>
      <div class="card-body">
        <div id="facet-filter"></div>
      </div>
    </div>
  </div>
  <div class="col-md-6">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">2. Dataset A (your data)</h5></div>
      <div class="card-body">
        <div class="form-check"><input class="form-check-input" type="radio" name="dataA-type" id="dataA-bed" value="bed" checked><label class="form-check-label" for="dataA-bed">Genomic regions (BED)</label></div>
        <div class="form-check"><input class="form-check-input" type="radio" name="dataA-type" id="dataA-genes" value="gene"><label class="form-check-label" for="dataA-genes">Gene list (symbols or IDs)</label></div>
        <div class="form-check mb-2"><input class="form-check-input" type="radio" name="dataA-type" id="dataA-count" value="count"><label class="form-check-label" for="dataA-count">Gene count table (CSV/TSV)</label></div>
        <textarea class="form-control mb-2" id="dataA-text" rows="6" placeholder="Paste content or use the file picker below."></textarea>
        <input type="file" id="dataA-file" class="form-control form-control-sm">
      </div>
    </div>
  </div>
</div>

<div class="row">
  <div class="col-md-6">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">3. Dataset B (compare with)</h5></div>
      <div class="card-body">
        <div class="form-check"><input class="form-check-input" type="radio" name="dataB-type" id="dataB-rnd" value="rnd" checked><label class="form-check-label" for="dataB-rnd">Random permutation of dataset A</label></div>
        <div id="permutation-row" class="ms-4 mb-2">
          <span class="form-check form-check-inline"><input class="form-check-input" type="radio" name="dataB-perm" id="perm-1" value="1" checked><label class="form-check-label" for="perm-1">×1</label></span>
          <span class="form-check form-check-inline"><input class="form-check-input" type="radio" name="dataB-perm" id="perm-10" value="10"><label class="form-check-label" for="perm-10">×10</label></span>
          <span class="form-check form-check-inline"><input class="form-check-input" type="radio" name="dataB-perm" id="perm-100" value="100"><label class="form-check-label" for="perm-100">×100</label></span>
        </div>
        <div class="form-check"><input class="form-check-input" type="radio" name="dataB-type" id="dataB-bed" value="bed"><label class="form-check-label" for="dataB-bed">Genomic regions (BED)</label></div>
        <div class="form-check"><input class="form-check-input" type="radio" name="dataB-type" id="dataB-refseq" value="refseq" disabled><label class="form-check-label" for="dataB-refseq">Refseq coding genes (gene-list mode only)</label></div>
        <div class="form-check mb-2"><input class="form-check-input" type="radio" name="dataB-type" id="dataB-userlist" value="userlist" disabled><label class="form-check-label" for="dataB-userlist">Gene list (gene-list mode only)</label></div>
        <textarea class="form-control mb-2" id="dataB-text" rows="6" placeholder="Paste content or use the file picker below." hidden></textarea>
        <input type="file" id="dataB-file" class="form-control form-control-sm" hidden>
        <p id="dataB-note" class="text-muted small mb-0">Random permutation needs no input.</p>
      </div>
    </div>
  </div>
  <div class="col-md-6">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">4. Analysis description</h5></div>
      <div class="card-body">
        <div class="mb-2">
          <label for="title" class="form-label small text-muted">Analysis title</label>
          <input type="text" id="title" class="form-control form-control-sm">
        </div>
        <div class="mb-2">
          <label for="dataA-title" class="form-label small text-muted">Dataset A title</label>
          <input type="text" id="dataA-title" class="form-control form-control-sm">
        </div>
        <div class="mb-3">
          <label for="dataB-title" class="form-label small text-muted">Dataset B title</label>
          <input type="text" id="dataB-title" class="form-control form-control-sm">
        </div>
        <div class="d-grid">
          <button type="button" id="submit-job" class="btn btn-primary btn-lg">Submit</button>
        </div>
        <div id="submit-status" class="text-muted small mt-2" aria-live="polite"></div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/enrichment-analysis.ts`**

Write:

```typescript
// frontend/pages/enrichment-analysis.ts
// GenomeTabs + FacetFilter + dataset A/B inputs (BED/genes/count, file upload) + job submit.

import { GenomeTabs } from '../components/genome-tabs'
import { FacetFilter } from '../components/facet-filter'
import { submitJob } from '../api/client'

interface PageData {
  genomes: Record<string, string>
  prefill: {
    taxonomy?: string
    genes?: string
    genesetA?: string
    genesetB?: string
  }
}

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function readFileToTextarea(input: HTMLInputElement, textarea: HTMLTextAreaElement): void {
  input.addEventListener('change', () => {
    const file = input.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => {
      textarea.value = String(reader.result || '')
    }
    reader.readAsText(file)
  })
}

function getCheckedValue(name: string): string {
  const r = document.querySelector<HTMLInputElement>(`input[name="${name}"]:checked`)
  return r?.value || ''
}

function syncDatasetBVisibility(): void {
  const aType = getCheckedValue('dataA-type')
  const bType = getCheckedValue('dataB-type')

  // Refseq + userlist are gene-list-mode only
  const isGeneMode = aType === 'gene'
  ;(document.getElementById('dataB-refseq') as HTMLInputElement).disabled = !isGeneMode
  ;(document.getElementById('dataB-userlist') as HTMLInputElement).disabled = !isGeneMode

  // Random permutation row visible only when dataset B = rnd
  ;($('permutation-row') as HTMLElement).hidden = bType !== 'rnd'

  // Textarea + file picker visible when dataset B needs content (bed or userlist)
  const needsInput = bType === 'bed' || bType === 'userlist'
  ;(document.getElementById('dataB-text') as HTMLElement).hidden = !needsInput
  ;(document.getElementById('dataB-file') as HTMLElement).hidden = !needsInput

  // Helper note
  const note = $('dataB-note')
  if (bType === 'rnd') note.textContent = 'Random permutation needs no input.'
  else if (bType === 'refseq') note.textContent = 'All Refseq coding genes (excluding dataset A) are used.'
  else if (needsInput) note.textContent = ''
  else note.textContent = ''
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const facet = $('facet-filter')
  const status = $('submit-status')

  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    if (FacetFilter.getCondition(facet)) {
      await FacetFilter.setGenome(facet, detail.genome)
    } else {
      await FacetFilter.init(facet, detail.genome)
    }
  })

  GenomeTabs.init(tabs, data.genomes)

  // Pre-fill from POST body if present
  if (data.prefill.genesetA) ($('dataA-text') as HTMLTextAreaElement).value = data.prefill.genesetA
  if (data.prefill.genesetB) ($('dataB-text') as HTMLTextAreaElement).value = data.prefill.genesetB
  else if (data.prefill.genes) ($('dataA-text') as HTMLTextAreaElement).value = data.prefill.genes

  document.querySelectorAll<HTMLInputElement>('input[name="dataA-type"], input[name="dataB-type"]').forEach((r) => {
    r.addEventListener('change', syncDatasetBVisibility)
  })
  syncDatasetBVisibility()

  readFileToTextarea(
    $('dataA-file') as HTMLInputElement,
    $('dataA-text') as HTMLTextAreaElement,
  )
  readFileToTextarea(
    $('dataB-file') as HTMLInputElement,
    $('dataB-text') as HTMLTextAreaElement,
  )

  $('submit-job').addEventListener('click', async () => {
    const condition = FacetFilter.getCondition(facet)
    if (!condition) { status.textContent = 'Filter not ready yet.'; return }

    const aType = getCheckedValue('dataA-type')
    const bType = getCheckedValue('dataB-type')
    const dataAText = ($('dataA-text') as HTMLTextAreaElement).value.trim()
    if (!dataAText) { status.textContent = 'Dataset A is empty.'; return }

    const params: Record<string, unknown> = {
      genome: condition.genome,
      track_class: condition.track_class,
      cell_type_class: condition.cell_type_class,
      qval: condition.qval,
      dataA_type: aType,
      dataA: dataAText,
      dataB_type: bType,
      title: ($('title') as HTMLInputElement).value,
      dataA_title: ($('dataA-title') as HTMLInputElement).value,
      dataB_title: ($('dataB-title') as HTMLInputElement).value,
    }
    if (bType === 'rnd') params.permutations = getCheckedValue('dataB-perm')
    if (bType === 'bed' || bType === 'userlist') params.dataB = ($('dataB-text') as HTMLTextAreaElement).value

    status.textContent = 'Submitting…'
    try {
      const result = await submitJob({ type: 'enrichment_analysis', params })
      window.location.href = `/enrichment_analysis_result?id=${encodeURIComponent(result.job_id)}&backend=${encodeURIComponent(result.backend)}`
    } catch (err) {
      console.error(err)
      status.textContent = 'Submit failed. Try again or check the service status.'
    }
  })
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build + Test**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/enrichment-analysis.js && echo "BUILD_OK"

PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/enrichment_analysis"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has page-data: #{body.include?(%q(id="page-data"))}"
  puts "Has facet-filter: #{body.include?(%q(id="facet-filter"))}"
  puts "Has dataA radios: #{body.include?(%q(name="dataA-type"))}"
  puts "Has dataB radios: #{body.include?(%q(name="dataB-type"))}"
  puts "Has submit button: #{body.include?(%q(id="submit-job"))}"
  puts "Has page_js: #{body.include?("/js/enrichment-analysis.js")}"

  post "/enrichment_analysis", { taxonomy: "hg38", genesetA: "MYC\\nTP53" }
  puts "POST status: #{last_response.status}"
  puts "POST has page-data: #{last_response.body.include?(%q(id="page-data"))}"
'
```

Expected: GET status 200, all GET assertions true. POST status 200 with page-data present.

- [ ] **Step 5: Commit**

Stage `routes/pages.rb`, `views/enrichment_analysis.erb`, `frontend/pages/enrichment-analysis.ts`. HEREDOC:

```
Convert /enrichment_analysis to ERB + TypeScript

GenomeTabs + FacetFilter for the experiment-side filter; three radio
modes for dataset A (BED, gene list, gene count table) with paste
textarea + FileReader-based file upload; four modes for dataset B
(random permutation with x1/x10/x100 toggle, BED, Refseq, gene list)
with conditional textarea visibility. Submit POSTs to /jobs/submit
and redirects to /enrichment_analysis_result?id=...&backend=... on
success. The legacy POST route still accepts taxonomy/genes/genesetA/
genesetB for prefill from external links.

The legacy ~1000-line jQuery enrichment_analysis.js is replaced with
~150 lines of TS. Live time-estimation during input is dropped
(legacy behavior); the result page shows real elapsed time via
JobTracker.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

### Task 10: Diff Analysis Page

**Files:**
- Create: `views/diff_analysis.erb`
- Create: `frontend/pages/diff-analysis.ts`
- Modify: `routes/pages.rb` (`/diff_analysis` route)
- Test: `GET /diff_analysis` returns 200

GenomeTabs + analysis-type radio (ChIP/ATAC/DNase-seq vs Bisulfite-seq) + two textareas for experiment IDs + estimated time.

- [ ] **Step 1: Update `/diff_analysis` route**

Find:

```ruby
        app.get '/diff_analysis' do
          load_analysis_settings
          haml :diff_analysis
        end
```

Replace:

```ruby
        app.get '/diff_analysis' do
          @list_of_genome = ChipAtlas::Experiment.list_of_genome
          @page_js = 'diff-analysis'
          erb :diff_analysis
        end
```

- [ ] **Step 2: Create `views/diff_analysis.erb`**

```erb
<%
  @page_title = 'Diff Analysis'
  @page_description = 'Detect differential peaks or differentially methylated regions.'
  @active_menu = 'diff_analysis'
%>
<script id="page-data" type="application/json"><%== { genomes: @list_of_genome }.to_json.gsub('</', '<\/') %></script>

<div class="row mb-3">
  <div class="col-md-12">
    <h1>ChIP-Atlas: Diff Analysis</h1>
    <p>Detect differential peaks or differentially methylated regions.</p>
  </div>
</div>

<div id="genome-tabs"></div>

<div class="row">
  <div class="col-md-3">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">1. Experiment type</h5></div>
      <div class="card-body">
        <div class="form-check">
          <input class="form-check-input" type="radio" name="analysis-type" id="analysis-diffbind" value="diffbind" checked>
          <label class="form-check-label" for="analysis-diffbind">ChIP / ATAC / DNase-seq</label>
        </div>
        <div class="form-check">
          <input class="form-check-input" type="radio" name="analysis-type" id="analysis-dmr" value="dmr">
          <label class="form-check-label" for="analysis-dmr">Bisulfite-seq</label>
        </div>
      </div>
    </div>
  </div>

  <div class="col-md-3">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">2. Dataset A (Experiment IDs)</h5></div>
      <div class="card-body">
        <textarea class="form-control" id="dataA-text" rows="8" placeholder="SRX or GSM ID(s), one per line"></textarea>
      </div>
    </div>
  </div>

  <div class="col-md-3">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">3. Dataset B (Experiment IDs)</h5></div>
      <div class="card-body">
        <textarea class="form-control" id="dataB-text" rows="8" placeholder="SRX or GSM ID(s), one per line"></textarea>
      </div>
    </div>
  </div>

  <div class="col-md-3">
    <div class="card mb-3">
      <div class="card-header"><h5 class="mb-0">4. Description</h5></div>
      <div class="card-body">
        <div class="mb-2">
          <label for="title" class="form-label small text-muted">Analysis title</label>
          <input type="text" id="title" class="form-control form-control-sm">
        </div>
        <div class="mb-2">
          <label for="dataA-title" class="form-label small text-muted">Dataset A title</label>
          <input type="text" id="dataA-title" class="form-control form-control-sm">
        </div>
        <div class="mb-3">
          <label for="dataB-title" class="form-label small text-muted">Dataset B title</label>
          <input type="text" id="dataB-title" class="form-control form-control-sm">
        </div>
        <div class="d-grid mb-2">
          <button type="button" id="submit-job" class="btn btn-primary btn-lg">Submit</button>
        </div>
        <div id="estimated-time" class="text-muted small">Estimated run time: —</div>
        <div id="submit-status" class="text-muted small mt-2" aria-live="polite"></div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Create `frontend/pages/diff-analysis.ts`**

```typescript
// frontend/pages/diff-analysis.ts
// GenomeTabs + analysis-type radio + two ID textareas + estimated time + job submit.

import { GenomeTabs } from '../components/genome-tabs'
import { submitJob, getEstimatedTime } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

let currentGenome = ''

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function getAnalysisType(): 'dmr' | 'diffbind' {
  const r = document.querySelector<HTMLInputElement>('input[name="analysis-type"]:checked')
  return r?.value === 'dmr' ? 'dmr' : 'diffbind'
}

function parseIds(text: string): string[] {
  return text.split(/[\s,]+/).map((s) => s.trim()).filter((s) => s.length > 0)
}

async function refreshEstimate(): Promise<void> {
  const ids = [
    ...parseIds(($('dataA-text') as HTMLTextAreaElement).value),
    ...parseIds(($('dataB-text') as HTMLTextAreaElement).value),
  ]
  const out = $('estimated-time')
  if (ids.length === 0) {
    out.textContent = 'Estimated run time: —'
    return
  }
  try {
    const res = await getEstimatedTime(ids, getAnalysisType())
    out.textContent = res.minutes != null ? `Estimated run time: ${res.minutes} min` : 'Estimated run time: —'
  } catch (err) {
    out.textContent = 'Estimated run time: (failed)'
  }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const status = $('submit-status')

  tabs.addEventListener('genome-change', (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
  })

  GenomeTabs.init(tabs, data.genomes)

  ;[$('dataA-text'), $('dataB-text')].forEach((el) => {
    let timer: number | null = null
    el.addEventListener('input', () => {
      if (timer != null) window.clearTimeout(timer)
      timer = window.setTimeout(refreshEstimate, 500)
    })
  })
  document.querySelectorAll<HTMLInputElement>('input[name="analysis-type"]').forEach((r) => {
    r.addEventListener('change', refreshEstimate)
  })

  $('submit-job').addEventListener('click', async () => {
    const idsA = parseIds(($('dataA-text') as HTMLTextAreaElement).value)
    const idsB = parseIds(($('dataB-text') as HTMLTextAreaElement).value)
    if (idsA.length === 0 || idsB.length === 0) {
      status.textContent = 'Both datasets must contain at least one experiment ID.'
      return
    }
    if (!currentGenome) {
      status.textContent = 'Select a genome tab first.'
      return
    }

    const params = {
      genome: currentGenome,
      analysis: getAnalysisType(),
      dataA_ids: idsA,
      dataB_ids: idsB,
      title: ($('title') as HTMLInputElement).value,
      dataA_title: ($('dataA-title') as HTMLInputElement).value,
      dataB_title: ($('dataB-title') as HTMLInputElement).value,
    }

    status.textContent = 'Submitting…'
    try {
      const result = await submitJob({ type: 'diff_analysis', params })
      window.location.href = `/diff_analysis_result?id=${encodeURIComponent(result.job_id)}&backend=${encodeURIComponent(result.backend)}`
    } catch (err) {
      console.error(err)
      status.textContent = 'Submit failed. Try again or check the service status.'
    }
  })
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 4: Build + Test**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
test -f /Users/inutano/repos/chip-atlas/public/js/diff-analysis.js && echo "BUILD_OK"

PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get "/diff_analysis"
  body = last_response.body
  puts "Status: #{last_response.status}"
  puts "Has page-data: #{body.include?(%q(id="page-data"))}"
  puts "Has analysis-type: #{body.include?(%q(name="analysis-type"))}"
  puts "Has dataA: #{body.include?(%q(id="dataA-text"))}"
  puts "Has dataB: #{body.include?(%q(id="dataB-text"))}"
  puts "Has submit: #{body.include?(%q(id="submit-job"))}"
  puts "Has estimate: #{body.include?(%q(id="estimated-time"))}"
  puts "Has page_js: #{body.include?("/js/diff-analysis.js")}"
'
```

Expected: Status 200, all assertions true.

- [ ] **Step 5: Commit**

Stage `routes/pages.rb`, `views/diff_analysis.erb`, `frontend/pages/diff-analysis.ts`. HEREDOC:

```
Convert /diff_analysis to ERB + TypeScript

GenomeTabs + analysis-type radio (ChIP-style diffbind vs Bisulfite
DMR) + two textareas for experiment IDs + live estimated time via
POST /jobs/estimated_time (debounced 500ms on textarea input).
Submit POSTs to /jobs/submit and redirects to /diff_analysis_result?
id=...&backend=...

Replaces ~290 lines of jQuery with ~110 lines of TS.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Final Verification

After all 10 tasks are complete:

```bash
cd /Users/inutano/repos/chip-atlas

# 1. TypeScript compiles cleanly across all pages and components
npx tsc --project frontend/tsconfig.json --noEmit && echo "TS: OK"

# 2. esbuild produces all expected bundles
node esbuild.config.mjs
for f in homepage search experiment target-genes target-genes-result colo colo-result \
         enrichment-result diff-result peak-browser enrichment-analysis diff-analysis; do
  test -f public/js/$f.js && echo "$f.js: OK" || echo "$f.js: MISSING"
done

# 3. All pages return 200 (analysis routes use minimal valid params)
PATH="/opt/homebrew/opt/ruby/bin:$PATH" RACK_ENV=test ruby -e '
  require "bundler/setup"
  require "rack/test"
  require_relative "app"
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  paths = [
    "/", "/publications", "/agents", "/demo",
    "/search", "/view?id=SRX038634",
    "/target_genes", "/target_genes_result?genome=hg38&track=CTCF&distance=5",
    "/colo", "/colo_result?genome=hg38&track=CTCF&cell_type=Neural",
    "/peak_browser", "/enrichment_analysis", "/diff_analysis",
    "/enrichment_analysis_result?id=abc&backend=wabi",
    "/diff_analysis_result?id=abc&backend=wabi",
  ]
  paths.each do |p|
    get p
    puts "#{p}: #{last_response.status}"
  end
  get "/this-does-not-exist"
  puts "404: #{last_response.status}"
'

# 4. Backend tests still pass
PATH="/opt/homebrew/opt/ruby/bin:$PATH" bundle exec ruby -Itest -e "Dir[%q(test/**/*_test.rb)].each { |f| require_relative f }" 2>&1 | tail -10
```

Expected:
- `TS: OK`
- All 12 `*.js` files built
- All 15 routes return 200, `404` returns 404
- 66 backend tests, 0 failures, 0 errors

After this plan ships, **every user-facing route is on the new ERB + TypeScript stack.** A subsequent cleanup plan can delete the legacy `views/*.haml` files and `public/js/pj/*.js` files.

---

## Dependencies Between Tasks

```
Task 1 (ColoIndex type)  ──── needed by Task 4
Task 2 (Target Genes setup)  ──── independent
Task 3 (Target Genes Result) ──── independent
Task 4 (Colo setup)          ──── depends on Task 1
Task 5 (Colo Result)         ──── independent
Task 6 (Enrichment Result)   ──── independent
Task 7 (Diff Result)         ──── independent
Task 8 (Peak Browser)        ──── independent
Task 9 (Enrichment Analysis) ──── independent (submit links to Task 6)
Task 10 (Diff Analysis)      ──── independent (submit links to Task 7)
```

Tasks 2, 3, 5, 6, 7, 8, 9, 10 are independent. Task 4 depends on Task 1. Recommended order is sequential as written: type fix first, then setup → result page pairs (Target Genes, Colo), then result pages (Enrichment, Diff), then the three flagship form pages (Peak Browser, Enrichment Analysis, Diff Analysis).
