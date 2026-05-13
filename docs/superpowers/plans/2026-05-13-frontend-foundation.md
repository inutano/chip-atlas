# Frontend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up the frontend build toolchain (esbuild + TypeScript), vendor Bootstrap 5, create the ERB layout template (navbar + footer), build the TypeScript API client, convert 4 static pages to ERB, and convert the homepage. This is Plan 1 of 3 -- it establishes the foundation that Plans 2 (shared components) and 3 (analysis pages) will build on.

**Architecture:** Sinatra app serving ERB templates. TypeScript compiled by esbuild into per-page JS bundles in `public/js/`. Bootstrap 5 CSS/JS vendored in `public/css/` and `public/js/`. One `layout.erb` shared by all pages. API client in `frontend/api/client.ts` provides typed fetch wrappers for all backend endpoints.

**Tech Stack:** TypeScript (strict mode, es2020), esbuild, Bootstrap 5.3.3, ERB (Ruby stdlib), kramdown (already in Gemfile)

**Reference:** Frontend design spec at `docs/superpowers/specs/2026-05-12-frontend-rebuild-design.md`. Current HAML views in `views/`. API routes in `routes/api.rb`, `routes/jobs.rb`, `routes/health.rb`.

**Important notes:**
- Ruby is at `/opt/homebrew/opt/ruby/bin/ruby`. Prefix Ruby/bundle commands with `PATH="/opt/homebrew/opt/ruby/bin:$PATH"`.
- Node.js is available via standard PATH.
- Existing HAML files are NOT deleted -- they stay until a later cleanup task. When `erb :template_name` is called and both `template.erb` and `template.haml` exist, Sinatra checks registered engines in order. Since the app has `set :erb, escape_html: true`, ERB is registered. Sinatra's `erb :about` will find `about.erb` first if it exists.
- However, Sinatra's `erb` method ONLY looks for `.erb` files. It will not fall back to `.haml`. The current HAML pages work because each HAML file is a complete HTML document (not using a shared layout). When we add `layout.erb`, the `erb :about` call will use `layout.erb` as the layout and `about.erb` as the content template. This is exactly what we want.
- The current HAML templates each define their OWN `<html>`, `<head>`, `<body>`, etc. -- they are standalone documents. The new ERB approach uses a shared `layout.erb` and thin content templates.

---

## File Structure (what this plan creates)

```
chip-atlas/
├── package.json                    # NEW: esbuild + typescript devDependencies
├── esbuild.config.mjs              # NEW: Build config
├── frontend/                       # NEW: TypeScript source
│   ├── tsconfig.json               # NEW: Strict mode, es2020
│   ├── api/
│   │   └── client.ts               # NEW: Typed API client
│   └── pages/
│       └── homepage.ts             # NEW: Homepage interactivity
├── views/
│   ├── layout.erb                  # NEW: Shared HTML shell
│   ├── _navbar.erb                 # NEW: Navigation partial
│   ├── _footer.erb                 # NEW: Footer partial
│   ├── about.erb                   # NEW: Homepage
│   ├── publications.erb            # NEW: Publications page
│   ├── agents.erb                  # NEW: Agent guide page
│   ├── demo.erb                    # NEW: Demo tutorial page
│   └── not_found.erb               # NEW: 404 page
├── public/
│   ├── css/
│   │   ├── bootstrap.min.css       # NEW: Bootstrap 5.3.3 (vendored)
│   │   └── style.css               # NEW: App-specific overrides
│   ├── js/
│   │   ├── bootstrap.bundle.min.js # NEW: Bootstrap 5.3.3 JS (vendored)
│   │   └── homepage.js             # GENERATED: esbuild output
│   └── icons/                      # NEW: Empty dir for future SVG icons
├── routes/
│   └── pages.rb                    # MODIFY: Add @page_js support
└── .gitignore                      # MODIFY: Ignore compiled JS, keep vendored
```

---

### Task 1: esbuild + TypeScript Setup

**Files:**
- Create: `package.json`
- Create: `frontend/tsconfig.json`
- Create: `esbuild.config.mjs`
- Create: `frontend/pages/homepage.ts`
- Modify: `.gitignore`
- Test: `node esbuild.config.mjs` produces `public/js/homepage.js`

- [ ] **Step 1: Create `package.json`**

```bash
cat > /Users/inutano/repos/chip-atlas/package.json << 'PKGJSON'
{
  "private": true,
  "scripts": {
    "build": "node esbuild.config.mjs",
    "watch": "node esbuild.config.mjs --watch"
  },
  "devDependencies": {
    "esbuild": "^0.21.0",
    "typescript": "^5.4.0"
  }
}
PKGJSON
```

- [ ] **Step 2: Create `frontend/tsconfig.json`**

```bash
mkdir -p /Users/inutano/repos/chip-atlas/frontend/api
mkdir -p /Users/inutano/repos/chip-atlas/frontend/pages
mkdir -p /Users/inutano/repos/chip-atlas/frontend/components
```

Write `frontend/tsconfig.json`:

```json
{
  "compilerOptions": {
    "strict": true,
    "target": "es2020",
    "module": "es2020",
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": false,
    "noEmit": true,
    "lib": ["es2020", "dom", "dom.iterable"],
    "baseUrl": ".",
    "paths": {
      "@api/*": ["api/*"],
      "@components/*": ["components/*"]
    }
  },
  "include": ["**/*.ts"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 3: Create `esbuild.config.mjs`**

```javascript
// esbuild.config.mjs
import * as esbuild from 'esbuild'
import { readdirSync } from 'fs'

// Auto-discover page entry points from frontend/pages/*.ts
const pageFiles = readdirSync('frontend/pages')
  .filter(f => f.endsWith('.ts'))
  .map(f => `frontend/pages/${f}`)

const isWatch = process.argv.includes('--watch')

const buildOptions = {
  entryPoints: pageFiles,
  bundle: true,
  outdir: 'public/js',
  format: 'esm',
  target: ['es2020'],
  minify: process.env.NODE_ENV === 'production',
  sourcemap: process.env.NODE_ENV !== 'production',
  logLevel: 'info',
}

if (isWatch) {
  const ctx = await esbuild.context(buildOptions)
  await ctx.watch()
  console.log('Watching for changes...')
} else {
  await esbuild.build(buildOptions)
}
```

- [ ] **Step 4: Create placeholder `frontend/pages/homepage.ts`**

```typescript
// frontend/pages/homepage.ts
console.log('ChIP-Atlas loaded')
```

- [ ] **Step 5: Update `.gitignore` to ignore compiled JS but keep vendored files**

Add the following lines to the end of `.gitignore`:

```
# Frontend build output (compiled TypeScript)
public/js/homepage.js
public/js/homepage.js.map
public/js/search.js
public/js/search.js.map
public/js/experiment.js
public/js/experiment.js.map
public/js/peak-browser.js
public/js/peak-browser.js.map
public/js/enrichment-analysis.js
public/js/enrichment-analysis.js.map
public/js/diff-analysis.js
public/js/diff-analysis.js.map
public/js/target-genes.js
public/js/target-genes.js.map
public/js/colo.js
public/js/colo.js.map
public/js/colo-result.js
public/js/colo-result.js.map
public/js/target-genes-result.js
public/js/target-genes-result.js.map
public/js/enrichment-result.js
public/js/enrichment-result.js.map
public/js/diff-result.js
public/js/diff-result.js.map
node_modules
```

- [ ] **Step 6: Install dependencies and test build**

```bash
cd /Users/inutano/repos/chip-atlas && npm install
```

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
```

**Expected:** Build succeeds, `public/js/homepage.js` is created. The output should show something like:

```
  public/js/homepage.js  XX bytes
```

Verify the file exists and contains compiled output:

```bash
test -f /Users/inutano/repos/chip-atlas/public/js/homepage.js && echo "OK: homepage.js exists" || echo "FAIL: homepage.js missing"
```

- [ ] **Step 7: Commit**

```
Add esbuild + TypeScript build toolchain

Set up the frontend build pipeline with esbuild for TypeScript
compilation. Each page gets its own entry point in frontend/pages/
that compiles to public/js/. Placeholder homepage.ts confirms the
build works.
```

---

### Task 2: Bootstrap 5 + style.css

**Files:**
- Create: `public/css/bootstrap.min.css` (download)
- Create: `public/js/bootstrap.bundle.min.js` (download)
- Create: `public/css/style.css`
- Create: `public/icons/` (empty directory)
- Test: Files exist and have expected sizes

- [ ] **Step 1: Download Bootstrap 5.3.3 CSS**

```bash
curl -sL "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" \
  -o /Users/inutano/repos/chip-atlas/public/css/bootstrap5.min.css
```

Note: We save as `bootstrap5.min.css` (not `bootstrap.min.css`) to avoid overwriting the existing Bootstrap 3 file which is still used by the HAML templates. The ERB layout will reference `bootstrap5.min.css`.

- [ ] **Step 2: Download Bootstrap 5.3.3 JS bundle**

```bash
curl -sL "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js" \
  -o /Users/inutano/repos/chip-atlas/public/js/bootstrap.bundle.min.js
```

- [ ] **Step 3: Create `public/css/style.css`**

```css
/* ChIP-Atlas custom styles — overrides for Bootstrap 5 */

/* ===== Colors ===== */
:root {
  --bs-primary: #337ab7;
  --bs-primary-rgb: 51, 122, 183;
  --bs-font-sans-serif: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --bs-body-font-size: 0.95rem;
}

.btn-primary {
  --bs-btn-bg: #337ab7;
  --bs-btn-border-color: #2e6da4;
  --bs-btn-hover-bg: #286090;
  --bs-btn-hover-border-color: #204d74;
}

/* ===== Body ===== */
body {
  padding-top: 70px;
}

/* ===== Navbar ===== */
.navbar {
  min-height: 50px;
}

.navbar .nav-link {
  padding-top: 15px;
  padding-bottom: 15px;
}

.navbar .nav-link i {
  margin-right: 5px;
}

#jumpToExperiment {
  width: 8em;
}

/* ===== Homepage feature cards ===== */
.feature-card {
  text-decoration: none !important;
  color: #333 !important;
}

.feature-card .card {
  height: 100%;
  transition: box-shadow 0.2s;
}

.feature-card:hover .card {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

.feature-card .card-body {
  display: flex;
  align-items: center;
  padding: 1.5rem;
}

.feature-card .feature-icon {
  font-size: 3.5rem;
  color: #337ab7;
  min-width: 80px;
  text-align: center;
}

.feature-card .badge {
  font-size: 0.75rem;
  padding: 0.4em 0.6em;
  margin-left: 3px;
}

/* ===== Footer ===== */
footer {
  margin-top: 10em;
  margin-bottom: 5em;
  text-align: center;
  text-transform: uppercase;
  font-style: italic;
  font-size: 66%;
}

footer .org-logo {
  margin-left: 30px;
  display: inline-block;
}

footer .org-logo img {
  width: 100px;
  height: auto;
}

footer .org-logo:nth-child(4) img,
footer .org-logo:nth-child(6) img {
  width: 150px;
}

footer .acknowledgement {
  margin-top: 2em;
}

/* ===== Responsive: abbreviations in navbar ===== */
.full-text {
  display: inline;
}

.abbrev-text {
  display: none;
}

@media (max-width: 1375px) {
  .full-text {
    display: none;
  }
  .abbrev-text {
    display: inline;
  }
  .navbar .nav-link {
    padding-left: 10px;
    padding-right: 10px;
  }
  #jumpToExperiment {
    width: 80px;
  }
}

@media (max-width: 767px) {
  footer .org-logo {
    margin-left: 10px;
  }
  footer .org-logo img {
    width: 20vw;
    max-width: 100px;
  }
  footer .org-logo:nth-child(4) img,
  footer .org-logo:nth-child(6) img {
    width: 28vw;
    max-width: 150px;
  }
}

/* ===== Markdown content pages (publications, agents, demo) ===== */
.markdown-content {
  margin-top: 0.5em;
  line-height: 1.5;
}

.markdown-content table {
  width: 100%;
  margin-bottom: 1em;
  border-collapse: collapse;
}

.markdown-content th,
.markdown-content td {
  padding: 8px 12px;
  border: 1px solid #ddd;
  text-align: left;
}

.markdown-content th {
  background-color: #f5f5f5;
  font-weight: bold;
}

.markdown-content tbody tr:hover {
  background-color: #f9f9f9;
}

/* ===== Copy button on code blocks ===== */
.copy-btn {
  position: absolute;
  top: 6px;
  right: 6px;
  background: #e8e8e8;
  border: none;
  border-radius: 3px;
  padding: 4px 7px;
  cursor: pointer;
  font-size: 13px;
  color: #555;
  opacity: 0.6;
  transition: opacity 0.15s;
}

.copy-btn:hover {
  background: #d0d0d0;
  color: #333;
  opacity: 1;
}
```

- [ ] **Step 4: Create `public/icons/` directory**

```bash
mkdir -p /Users/inutano/repos/chip-atlas/public/icons
touch /Users/inutano/repos/chip-atlas/public/icons/.gitkeep
```

- [ ] **Step 5: Verify files exist and have expected sizes**

```bash
echo "=== Bootstrap 5 CSS ===" && \
wc -c /Users/inutano/repos/chip-atlas/public/css/bootstrap5.min.css && \
echo "=== Bootstrap 5 JS ===" && \
wc -c /Users/inutano/repos/chip-atlas/public/js/bootstrap.bundle.min.js && \
echo "=== style.css ===" && \
wc -c /Users/inutano/repos/chip-atlas/public/css/style.css && \
echo "=== icons dir ===" && \
test -d /Users/inutano/repos/chip-atlas/public/icons && echo "OK: icons/ exists" || echo "FAIL"
```

**Expected:**
- `bootstrap5.min.css` should be ~190KB (uncompressed)
- `bootstrap.bundle.min.js` should be ~80KB (uncompressed)
- `style.css` should be ~150-180 lines
- `public/icons/` directory exists

- [ ] **Step 6: Commit**

```
Vendor Bootstrap 5.3.3 and add app-specific style.css

Download Bootstrap 5.3.3 CSS (as bootstrap5.min.css to coexist with
the existing Bootstrap 3 file) and JS bundle. Create style.css with
app-specific overrides extracted from the current style.sass: primary
color, navbar, feature cards, footer, responsive abbreviations.
```

---

### Task 3: TypeScript API Client

**Files:**
- Create: `frontend/api/client.ts`
- Test: `cd frontend && npx tsc --noEmit` compiles without errors

- [ ] **Step 1: Create `frontend/api/client.ts`**

This client provides typed fetch wrappers for every endpoint in `routes/api.rb`, `routes/jobs.rb`, and `routes/health.rb`.

```typescript
// frontend/api/client.ts
// Typed API client for ChIP-Atlas backend

// ===== Interfaces =====

export interface GenomeInfo {
  [genome: string]: string  // e.g. { "hg38": "Homo sapiens", "mm10": "Mus musculus" }
}

export interface Stats {
  total_experiments: number
  formatted_count: string
  by_genome: Record<string, number>
}

export interface ClassificationItem {
  name: string
  count: number
}

export interface SubclassItem {
  name: string
}

export interface ExperimentRecord {
  experiment_id: string
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  [key: string]: unknown
}

export interface SearchResult {
  results: ExperimentRecord[]
  total: number
  limit: number
  offset: number
}

export interface QvalRange {
  [key: string]: string  // e.g. { "50": "50", "100": "100", ... }
}

export interface BedSizes {
  [key: string]: number
}

export interface ColoIndex {
  [track: string]: string[]  // track -> cell_types
}

export interface TargetGenesIndex {
  [genome: string]: string[]  // genome -> tracks
}

export interface IgvUrlResponse {
  url: string
}

export interface DownloadUrlResponse {
  url: string
}

export interface ColoData {
  [key: string]: unknown
}

export interface TargetGenesData {
  [key: string]: unknown
}

export interface UrlCondition {
  genome: string
  track_class: string
  track_subclass?: string
  cell_type_class?: string
  cell_type_subclass?: string
  qval?: string
  track?: string
  cell_type?: string
  distance?: string
}

export interface JobSubmission {
  type: 'enrichment_analysis' | 'diff_analysis'
  params: Record<string, unknown>
}

export interface JobSubmitResult {
  backend: string
  job_id: string
}

export interface JobStatus {
  backend: string
  job_id: string
  status: string
  retry: boolean
}

export interface JobResult {
  backend: string
  job_id: string
  urls: Record<string, string>
}

export interface JobAvailability {
  backend: string | null
  available: boolean
}

export interface EstimatedTime {
  minutes: number | null
}

export interface HealthCheck {
  status: string
  checks: {
    database: string
    experiments: string
    database_error?: string
  }
}

export interface ServiceStatus {
  [service: string]: boolean | string
}

// ===== Error handling =====

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly statusText: string,
    public readonly body: string
  ) {
    super(`API error ${status}: ${statusText}`)
    this.name = 'ApiError'
  }
}

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init)
  if (!response.ok) {
    const body = await response.text()
    throw new ApiError(response.status, response.statusText, body)
  }
  return response.json() as Promise<T>
}

async function requestText(url: string, init?: RequestInit): Promise<string> {
  const response = await fetch(url, init)
  if (!response.ok) {
    const body = await response.text()
    throw new ApiError(response.status, response.statusText, body)
  }
  return response.text()
}

function qs(params: Record<string, string | number | undefined>): string {
  const entries = Object.entries(params)
    .filter((pair): pair is [string, string | number] => pair[1] !== undefined)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
  return entries.length > 0 ? `?${entries.join('&')}` : ''
}

// ===== Classification endpoints =====

export async function listGenomes(): Promise<GenomeInfo> {
  return request<GenomeInfo>('/api/genomes')
}

export async function getStats(): Promise<Stats> {
  return request<Stats>('/api/stats')
}

export async function listTrackClasses(
  genome?: string,
  cellTypeClass?: string
): Promise<ClassificationItem[] | Record<string, ClassificationItem[]>> {
  const params: Record<string, string | undefined> = {
    genome,
    cell_type_class: cellTypeClass,
  }
  return request('/api/track_classes' + qs(params))
}

export async function listCellTypeClasses(
  genome: string,
  trackClass: string
): Promise<ClassificationItem[]> {
  return request<ClassificationItem[]>(
    '/api/cell_type_classes' + qs({ genome, track_class: trackClass })
  )
}

export async function listTrackSubclasses(
  genome: string,
  trackClass: string,
  cellTypeClass?: string
): Promise<SubclassItem[]> {
  return request<SubclassItem[]>(
    '/api/track_subclasses' + qs({ genome, track_class: trackClass, cell_type_class: cellTypeClass })
  )
}

export async function listCellTypeSubclasses(
  genome: string,
  trackClass: string,
  cellTypeClass?: string
): Promise<SubclassItem[]> {
  return request<SubclassItem[]>(
    '/api/cell_type_subclasses' + qs({ genome, track_class: trackClass, cell_type_class: cellTypeClass })
  )
}

// ===== Data endpoints =====

export async function getGenomeIndex(): Promise<Record<string, unknown>> {
  return request<Record<string, unknown>>('/api/genome_index')
}

export async function getExperiment(experimentId: string): Promise<ExperimentRecord> {
  return request<ExperimentRecord>(
    '/api/experiment' + qs({ experiment_id: experimentId })
  )
}

export async function searchExperiments(
  query?: string,
  genome?: string,
  limit?: number,
  offset?: number
): Promise<SearchResult> {
  return request<SearchResult>(
    '/api/search' + qs({ q: query, genome, limit, offset })
  )
}

export async function getQvalRange(): Promise<QvalRange> {
  return request<QvalRange>('/api/qval_range')
}

export async function getBedSizes(): Promise<BedSizes> {
  return request<BedSizes>('/api/bed_sizes')
}

// ===== Analysis index endpoints =====

export async function getColoIndex(genome: string): Promise<ColoIndex> {
  return request<ColoIndex>('/api/colo_index' + qs({ genome }))
}

export async function getTargetGenesIndex(): Promise<TargetGenesIndex> {
  return request<TargetGenesIndex>('/api/target_genes_index')
}

export async function getTargetGenesDistances(): Promise<string[]> {
  return request<string[]>('/api/target_genes_distances')
}

// ===== URL generation endpoints =====

export async function getIgvUrl(condition: UrlCondition): Promise<IgvUrlResponse> {
  return request<IgvUrlResponse>('/api/igv_url', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ condition }),
  })
}

export async function getDownloadUrl(condition: UrlCondition): Promise<DownloadUrlResponse> {
  return request<DownloadUrlResponse>('/api/download_url', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ condition }),
  })
}

// ===== Colocalization data =====

export async function getColoData(
  genome: string,
  track: string,
  cellType: string
): Promise<ColoData> {
  return request<ColoData>(
    '/api/colo' + qs({ genome, track, cell_type: cellType })
  )
}

export async function downloadColoFile(
  genome: string,
  track: string,
  cellType: string,
  format: 'tsv' | 'gml'
): Promise<string> {
  return requestText(
    '/api/colo/download' + qs({ genome, track, cell_type: cellType, format })
  )
}

// ===== Target genes data =====

export async function getTargetGenesData(
  genome: string,
  track: string,
  distance: string
): Promise<TargetGenesData> {
  return request<TargetGenesData>(
    '/api/target_genes' + qs({ genome, track, distance })
  )
}

export async function downloadTargetGenesFile(
  genome: string,
  track: string,
  distance: string,
  format: 'tsv'
): Promise<string> {
  return requestText(
    '/api/target_genes/download' + qs({ genome, track, distance, format })
  )
}

// ===== Job endpoints =====

export async function checkJobAvailability(
  type: string = 'enrichment_analysis'
): Promise<JobAvailability> {
  return request<JobAvailability>('/jobs/available' + qs({ type }))
}

export async function submitJob(submission: JobSubmission): Promise<JobSubmitResult> {
  return request<JobSubmitResult>('/jobs/submit', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(submission),
  })
}

export async function getJobStatus(id: string, backend: string): Promise<JobStatus> {
  return request<JobStatus>(`/jobs/${encodeURIComponent(id)}/status` + qs({ backend }))
}

export async function getJobResult(id: string, backend: string): Promise<JobResult> {
  return request<JobResult>(`/jobs/${encodeURIComponent(id)}/result` + qs({ backend }))
}

export async function getJobLog(id: string, backend: string): Promise<string> {
  return requestText(`/jobs/${encodeURIComponent(id)}/log` + qs({ backend }))
}

export async function getEstimatedTime(
  ids: string[],
  analysis: 'dmr' | 'diffbind'
): Promise<EstimatedTime> {
  return request<EstimatedTime>('/jobs/estimated_time', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ids, analysis }),
  })
}

// ===== Health / status endpoints =====

export async function healthCheck(): Promise<HealthCheck> {
  return request<HealthCheck>('/health')
}

export async function serviceStatus(): Promise<ServiceStatus> {
  return request<ServiceStatus>('/status')
}

// ===== Internal endpoints =====

export async function checkRemoteUrlStatus(url: string): Promise<string> {
  return requestText('/api/remote_url_status' + qs({ url }))
}
```

- [ ] **Step 2: Verify TypeScript compiles without errors**

```bash
cd /Users/inutano/repos/chip-atlas && npx tsc --project frontend/tsconfig.json --noEmit
```

**Expected:** No output (no errors). Exit code 0.

If there are errors, fix them before proceeding.

- [ ] **Step 3: Commit**

```
Add TypeScript API client with typed wrappers for all endpoints

Create frontend/api/client.ts with interfaces and functions covering
all API, job, and health endpoints. Every function maps to an exact
route in routes/api.rb, routes/jobs.rb, and routes/health.rb.
```

---

### Task 4: ERB Layout Template

**Files:**
- Create: `views/layout.erb`
- Create: `views/_navbar.erb`
- Create: `views/_footer.erb`
- Modify: `routes/pages.rb`
- Test: `GET /` returns 200 with Bootstrap 5 classes

**Important:** Sinatra's `erb :about` will look for `views/about.erb`. If it exists, it uses that. If not, it raises an error -- it does NOT fall back to `about.haml`. The `layout.erb` file is automatically used as the layout for all `erb` calls unless `layout: false` is specified. The HAML templates (which are standalone full-HTML documents) will continue to work because routes that still call `haml :template` will use HAML rendering. But since we are changing routes to call `erb :about`, we need `about.erb` to exist (covered in Task 6).

- [ ] **Step 1: Create `views/layout.erb`**

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="<%= @page_description || 'Browse and analyse public ChIP-Seq/DNase-Seq/ATAC-Seq/Bisulfite-Seq data.' %>">
  <meta name="author" content="Shinya Oki, Tazro Ohta">
  <title><%= @page_title ? "ChIP-Atlas: #{@page_title}" : "ChIP-Atlas" %></title>
  <link rel="stylesheet" href="/css/bootstrap5.min.css">
  <link rel="stylesheet" href="/css/style.css">
</head>
<body>
  <%= erb :_navbar %>
  <div class="container">
    <%= yield %>
  </div>
  <%= erb :_footer %>
  <script src="/js/bootstrap.bundle.min.js"></script>
  <% if @page_js %>
    <script type="module" src="/js/<%= @page_js %>.js"></script>
  <% end %>
</body>
</html>
```

- [ ] **Step 2: Create `views/_navbar.erb`**

Translated from `views/_navigation.haml`. Uses Bootstrap 5 navbar classes instead of Bootstrap 3.

```erb
<nav class="navbar navbar-expand-lg navbar-dark bg-dark fixed-top">
  <div class="container-fluid">
    <a class="navbar-brand" href="/">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="currentColor" viewBox="0 0 16 16">
        <path d="M8 1l2 5h5l-4 3 1.5 5L8 11 3.5 14 5 9 1 6h5z"/>
      </svg>
    </a>
    <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbar-collapse-main" aria-controls="navbar-collapse-main" aria-expanded="false" aria-label="Toggle navigation">
      <span class="navbar-toggler-icon"></span>
    </button>
    <div class="collapse navbar-collapse" id="navbar-collapse-main">
      <ul class="navbar-nav me-auto">
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'peak_browser' %>" href="/peak_browser">
            <span class="full-text">Peak Browser</span>
            <span class="abbrev-text">PB</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'enrichment_analysis' %>" href="/enrichment_analysis">
            <span class="full-text">Enrichment Analysis</span>
            <span class="abbrev-text">EA</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'diff_analysis' %>" href="/diff_analysis">
            <span class="full-text">Diff Analysis</span>
            <span class="abbrev-text">DA</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'target_genes' %>" href="/target_genes">
            <span class="full-text">Target Genes</span>
            <span class="abbrev-text">TG</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'colo' %>" href="/colo">
            <span class="full-text">Colo</span>
            <span class="abbrev-text">Colo</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'publications' %>" href="/publications">
            <span class="full-text">Publications</span>
            <span class="abbrev-text">Pub</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link<%= ' active' if @active_menu == 'agents' %>" href="/agents">
            <span class="full-text">Agents</span>
            <span class="abbrev-text">API</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link" href="https://github.com/inutano/chip-atlas/wiki">
            <span class="full-text">Docs</span>
            <span class="abbrev-text">Doc</span>
          </a>
        </li>
      </ul>
      <div class="d-flex align-items-center">
        <a class="nav-link text-light me-3" href="/search">
          <span class="full-text">Search</span>
          <span class="abbrev-text">?</span>
        </a>
        <span class="text-light me-2">
          <span class="full-text">ID:</span>
          <span class="abbrev-text">ID:</span>
        </span>
        <form class="d-flex" role="search" onsubmit="event.preventDefault(); window.open('/view?id=' + document.getElementById('jumpToExperiment').value);">
          <input class="form-control form-control-sm me-2" type="text" id="jumpToExperiment" value="SRX018625" aria-label="Experiment ID">
          <button class="btn btn-outline-light btn-sm" type="submit">Go</button>
        </form>
      </div>
    </div>
  </div>
</nav>
```

- [ ] **Step 3: Create `views/_footer.erb`**

Translated from `views/footer.haml`. Same logos, same attribution text.

```erb
<footer class="footer">
  <div class="container">
    <div class="row">
      <div class="col-12">
        <span class="org-logo">
          <a href="https://ewww.kumamoto-u.ac.jp/en/" target="_blank">
            <img src="/images/logo/kumamoto_uni_logo.jpg" alt="Kumamoto University">
          </a>
        </span>
        <span class="org-logo">
          <a href="https://www.ddbj.nig.ac.jp/index-e.html" target="_blank">
            <img src="/images/logo/ddbj_logo.png" alt="DDBJ">
          </a>
        </span>
        <span class="org-logo">
          <a href="https://biosciencedbc.jp/en/" target="_blank">
            <img src="/images/logo/nbdc_logo.png" alt="NBDC">
          </a>
        </span>
        <span class="org-logo">
          <a href="https://www.jst.go.jp/EN/" target="_blank">
            <img src="/images/logo/jst_logo.png" alt="JST">
          </a>
        </span>
        <span class="org-logo">
          <a href="https://dbcls.rois.ac.jp" target="_blank">
            <img src="/images/logo/dbcls_logo.png" alt="DBCLS">
          </a>
        </span>
        <span class="org-logo">
          <a href="https://www.m.chiba-u.ac.jp/dept/chiba_ai/" target="_blank">
            <img src="/images/logo/chiba_uni_logo.png" alt="Chiba University">
          </a>
        </span>
      </div>
    </div>
    <div class="row">
      <div class="col-12">
        <p class="acknowledgement">
          This work is supported by
          <a href="https://sc.ddbj.nig.ac.jp/">NIG Supercomputer system</a>
          and
          <a href="https://biosciencedbc.jp">JST NBDC JPMJND2202.</a>
        </p>
        <p>
          All data and analysis tools provided by ChIP-Atlas are licensed under
          <a href="https://creativecommons.org/licenses/by/4.0/">CC-BY 4.0</a>.
          Attribution should be made to our
          <a href="https://chip-atlas.org/publications">publication</a>
          when using these resources.
        </p>
        <p>
          If something went wrong, check
          <a href="https://sc.ddbj.nig.ac.jp/en/blog/tags/maintenance/" target="_blank">NIG Supercomputer system maintenance information.</a>
          Need help? Create an issue on
          <a href="https://github.com/inutano/chip-atlas/issues" target="_blank">GitHub</a>
          or
          <a href="mailto:okishinya@kumamoto-u.ac.jp?cc=zou@kumamoto-u.ac.jp">contact us</a>
        </p>
      </div>
    </div>
  </div>
</footer>
```

- [ ] **Step 4: Modify `routes/pages.rb` — add `@page_js` and `@active_menu` support, switch homepage to ERB**

Replace the `get '/'` route to use ERB and set `@page_js`. Also add `@active_menu` defaults.

In `routes/pages.rb`, replace the entire `get '/'` block:

```ruby
# FIND this:
        app.get '/' do
          @number_of_experiments = ChipAtlas::Experiment.formatted_experiment_count
          erb :about
        end

# REPLACE with:
        app.get '/' do
          @number_of_experiments = ChipAtlas::Experiment.formatted_experiment_count
          @page_js = 'homepage'
          erb :about
        end
```

Also update the static page routes to set `@active_menu`:

```ruby
# FIND this:
        app.get '/publications' do
          erb :publications
        end

# REPLACE with:
        app.get '/publications' do
          @active_menu = 'publications'
          erb :publications
        end
```

```ruby
# FIND this:
        app.get '/agents' do
          erb :agents
        end

# REPLACE with:
        app.get '/agents' do
          @active_menu = 'agents'
          erb :agents
        end
```

```ruby
# FIND this:
        app.get '/demo' do
          erb :demo
        end

# REPLACE with:
        app.get '/demo' do
          @active_menu = 'demo'
          erb :demo
        end
```

- [ ] **Step 5: Test the layout**

Note: This step requires the homepage ERB (`about.erb`) to exist. If you are executing tasks sequentially, skip this test and run it after Task 6. If you are executing tasks in parallel, create a minimal `about.erb` placeholder first:

```bash
echo '<h1>ChIP-Atlas</h1>' > /Users/inutano/repos/chip-atlas/views/about.erb
```

Then test:

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
ruby -e "
  require 'bundler/setup'
  require 'rack/test'
  require_relative 'app'
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get '/'
  puts \"Status: #{last_response.status}\"
  puts \"Has Bootstrap 5: #{last_response.body.include?('bootstrap5.min.css')}\"
  puts \"Has navbar: #{last_response.body.include?('navbar-expand-lg')}\"
  puts \"Has footer: #{last_response.body.include?('footer')}\"
"
```

**Expected output:**
```
Status: 200
Has Bootstrap 5: true
Has navbar: true
Has footer: true
```

Remove the placeholder if you created one (Task 6 will create the real one):
```bash
rm -f /Users/inutano/repos/chip-atlas/views/about.erb
```

- [ ] **Step 6: Commit**

```
Add ERB layout with Bootstrap 5 navbar and footer

Create layout.erb as the shared HTML shell for all pages. Translate
the HAML navbar and footer to ERB with Bootstrap 5 classes. Add
@page_js instance variable for per-page JS loading and @active_menu
for navbar highlighting.
```

---

### Task 5: Static Pages (Publications, Agents, Demo, 404)

**Files:**
- Create: `views/publications.erb`
- Create: `views/agents.erb`
- Create: `views/demo.erb`
- Create: `views/not_found.erb`
- Test: GET /publications, /agents, /demo all return 200

These pages use kramdown to render their `.markdown` files, same as the current HAML versions. They inherit from `layout.erb` so they are very thin.

- [ ] **Step 1: Create `views/publications.erb`**

```erb
<%
  @page_title = 'Publications'
  @page_description = 'The list of publications that used ChIP-Atlas database.'
  @active_menu = 'publications'
%>
<div class="row">
  <div class="col-md-8 offset-md-2 markdown-content">
    <%= Kramdown::Document.new(File.read(File.join(settings.views, 'publications.markdown')), input: 'GFM', hard_wrap: false).to_html %>
  </div>
</div>
```

- [ ] **Step 2: Create `views/agents.erb`**

```erb
<%
  @page_title = 'Agent Guide'
  @page_description = 'Guide for AI agents to use ChIP-Atlas MCP tools and API endpoints.'
  @active_menu = 'agents'
%>
<div class="row">
  <div class="col-md-8 offset-md-2 markdown-content">
    <%= Kramdown::Document.new(File.read(File.join(settings.views, 'agents.markdown')), input: 'GFM', hard_wrap: false).to_html %>
  </div>
</div>
<script>
  // Copy button for code blocks (ported from _copy_code.haml)
  document.addEventListener('DOMContentLoaded', function() {
    function copyText(text) {
      if (navigator.clipboard && window.isSecureContext) {
        return navigator.clipboard.writeText(text);
      }
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      try { document.execCommand('copy'); } catch(e) {}
      document.body.removeChild(ta);
      return Promise.resolve();
    }

    document.querySelectorAll('.markdown-content pre').forEach(function(pre) {
      pre.style.position = 'relative';
      var btn = document.createElement('button');
      btn.className = 'copy-btn';
      btn.title = 'Copy to clipboard';
      btn.textContent = 'Copy';
      btn.addEventListener('click', function() {
        var code = pre.querySelector('code');
        var text = (code || pre).textContent.replace(/\n$/, '');
        copyText(text).then(function() {
          btn.textContent = 'Copied!';
          setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
        });
      });
      pre.appendChild(btn);
    });
  });
</script>
```

- [ ] **Step 3: Create `views/demo.erb`**

```erb
<%
  @page_title = 'Demo Tutorial'
  @page_description = 'Step-by-step tutorial for using ChIP-Atlas with AI agents via llms.txt, MCP server, and HTTP API.'
  @active_menu = 'demo'
%>
<div class="row">
  <div class="col-md-8 offset-md-2 markdown-content">
    <%= Kramdown::Document.new(File.read(File.join(settings.views, 'demo.markdown')), input: 'GFM', hard_wrap: false).to_html %>
  </div>
</div>
<script>
  // Copy button for code blocks (ported from _copy_code.haml)
  document.addEventListener('DOMContentLoaded', function() {
    function copyText(text) {
      if (navigator.clipboard && window.isSecureContext) {
        return navigator.clipboard.writeText(text);
      }
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      try { document.execCommand('copy'); } catch(e) {}
      document.body.removeChild(ta);
      return Promise.resolve();
    }

    document.querySelectorAll('.markdown-content pre').forEach(function(pre) {
      pre.style.position = 'relative';
      var btn = document.createElement('button');
      btn.className = 'copy-btn';
      btn.title = 'Copy to clipboard';
      btn.textContent = 'Copy';
      btn.addEventListener('click', function() {
        var code = pre.querySelector('code');
        var text = (code || pre).textContent.replace(/\n$/, '');
        copyText(text).then(function() {
          btn.textContent = 'Copied!';
          setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
        });
      });
      pre.appendChild(btn);
    });
  });
</script>
```

- [ ] **Step 4: Create `views/not_found.erb`**

```erb
<%
  @page_title = '404'
  @page_description = 'Page not found.'
  @active_menu = nil
%>
<div class="row">
  <div class="col-md-10">
    <h1>ChIP-Atlas: 404</h1>
  </div>
  <div class="col-md-10">
    <p>Sorry, could not find the requested resource. Try with different data or contact us.</p>
    <p>
      <a href="/" class="btn btn-primary">Back to Home</a>
      <a href="https://github.com/inutano/chip-atlas/issues" class="btn btn-outline-secondary" target="_blank">Report Issue</a>
    </p>
  </div>
</div>
```

- [ ] **Step 5: Update `routes/pages.rb` — remove `@active_menu` from route blocks since it is now set in the ERB templates**

The static pages now set `@active_menu` inside their ERB templates (Step 1-4 above), so the route-level `@active_menu` assignments from Task 4 Step 4 are redundant. Remove them to keep routes clean:

```ruby
# FIND this (from Task 4):
        app.get '/publications' do
          @active_menu = 'publications'
          erb :publications
        end

# REPLACE with:
        app.get '/publications' do
          erb :publications
        end
```

```ruby
# FIND this (from Task 4):
        app.get '/agents' do
          @active_menu = 'agents'
          erb :agents
        end

# REPLACE with:
        app.get '/agents' do
          erb :agents
        end
```

```ruby
# FIND this (from Task 4):
        app.get '/demo' do
          @active_menu = 'demo'
          erb :demo
        end

# REPLACE with:
        app.get '/demo' do
          erb :demo
        end
```

Note: This reverts the `routes/pages.rb` changes from Task 4 Step 4 for these three routes. The `@active_menu` is set inside each ERB template instead, which is cleaner -- it keeps all page metadata (title, description, active menu) in one place.

- [ ] **Step 6: Test all static pages**

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
ruby -e "
  require 'bundler/setup'
  require 'rack/test'
  require_relative 'app'
  include Rack::Test::Methods
  def app; ChipAtlasApp; end

  ['/publications', '/agents', '/demo'].each do |path|
    get path
    status = last_response.status
    has_bootstrap = last_response.body.include?('bootstrap5.min.css')
    has_content = last_response.body.include?('markdown-content')
    puts \"#{path}: status=#{status} bootstrap5=#{has_bootstrap} content=#{has_content}\"
  end

  get '/nonexistent-page-that-does-not-exist'
  puts \"404: status=#{last_response.status} has_404=#{last_response.body.include?('404')}\"
"
```

**Expected output:**
```
/publications: status=200 bootstrap5=true content=true
/agents: status=200 bootstrap5=true content=true
/demo: status=200 bootstrap5=true content=true
404: status=404 has_404=true
```

- [ ] **Step 7: Commit**

```
Convert publications, agents, demo, and 404 pages to ERB

Thin ERB templates that render markdown via kramdown and inherit from
layout.erb. No JavaScript needed. Copy-to-clipboard button inlined
for agents and demo pages (replaces _copy_code.haml partial).
```

---

### Task 6: Homepage

**Files:**
- Create: `views/about.erb`
- Modify: `frontend/pages/homepage.ts`
- Build: `node esbuild.config.mjs`
- Test: GET / returns 200 with "ChIP-Atlas" in body

The homepage has 6 feature cards linking to each tool, plus a "What's new" section rendered from `updates.markdown`. The TypeScript fetches `/api/stats` and updates the experiment count.

- [ ] **Step 1: Create `views/about.erb`**

```erb
<%
  @page_title = nil
  @page_description = 'Browse and analyse the public ChIP-Seq/DNase-Seq/ATAC-Seq/Bisulfite-Seq data on your browser.'
  @active_menu = nil
%>
<div class="page-header mb-4">
  <h1>ChIP-Atlas</h1>
  <p class="lead">
    A data-mining suite for exploring epigenomic landscapes by fully integrating
    <span id="experiment-count"><%= @number_of_experiments %></span>
    ChIP-seq, ATAC-seq and Bisulfite-seq experiments.
  </p>
</div>

<div class="row g-3 mb-3">
  <div class="col-md-4">
    <a href="/peak_browser" class="feature-card">
      <div class="card">
        <div class="card-body">
          <div class="feature-icon">&#x1F50D;</div>
          <div class="ms-3">
            <h5 class="card-title mb-1">Peak Browser</h5>
            <div>
              <span class="badge bg-primary">ChIP</span>
              <span class="badge bg-primary">ATAC</span>
              <span class="badge bg-primary">Bisulfite</span>
            </div>
          </div>
        </div>
      </div>
    </a>
  </div>
  <div class="col-md-4">
    <a href="/enrichment_analysis" class="feature-card">
      <div class="card">
        <div class="card-body">
          <div class="feature-icon">&#x2764;</div>
          <div class="ms-3">
            <h5 class="card-title mb-1">Enrichment Analysis</h5>
            <div>
              <span class="badge bg-primary">ChIP</span>
              <span class="badge bg-primary">ATAC</span>
              <span class="badge bg-primary">Bisulfite</span>
            </div>
          </div>
        </div>
      </div>
    </a>
  </div>
  <div class="col-md-4">
    <a href="/diff_analysis" class="feature-card">
      <div class="card">
        <div class="card-body">
          <div class="feature-icon">&#x2696;</div>
          <div class="ms-3">
            <h5 class="card-title mb-1">Diff Analysis</h5>
            <div>
              <span class="badge bg-primary">ChIP</span>
              <span class="badge bg-primary">ATAC</span>
              <span class="badge bg-primary">Bisulfite</span>
            </div>
          </div>
        </div>
      </div>
    </a>
  </div>
</div>

<div class="row g-3 mb-4">
  <div class="col-md-4">
    <a href="/target_genes" class="feature-card">
      <div class="card">
        <div class="card-body">
          <div class="feature-icon">&#x1F3AF;</div>
          <div class="ms-3">
            <h5 class="card-title mb-1">Target Genes</h5>
            <div>
              <span class="badge bg-primary">ChIP</span>
            </div>
          </div>
        </div>
      </div>
    </a>
  </div>
  <div class="col-md-4">
    <a href="/colo" class="feature-card">
      <div class="card">
        <div class="card-body">
          <div class="feature-icon">&#x1F517;</div>
          <div class="ms-3">
            <h5 class="card-title mb-1">Colocalization</h5>
            <div>
              <span class="badge bg-primary">ChIP</span>
            </div>
          </div>
        </div>
      </div>
    </a>
  </div>
  <div class="col-md-4">
    <a href="/search" class="feature-card">
      <div class="card">
        <div class="card-body">
          <div class="feature-icon">&#x1F50E;</div>
          <div class="ms-3">
            <h5 class="card-title mb-1">Dataset Search</h5>
            <div>
              <span class="badge bg-primary">ChIP</span>
              <span class="badge bg-primary">ATAC</span>
              <span class="badge bg-primary">Bisulfite</span>
            </div>
          </div>
        </div>
      </div>
    </a>
  </div>
</div>

<div class="row">
  <div class="col-md-10 offset-md-1 markdown-content">
    <%= Kramdown::Document.new(File.read(File.join(settings.views, 'updates.markdown')), input: 'GFM', hard_wrap: false).to_html %>
  </div>
</div>
```

- [ ] **Step 2: Update `frontend/pages/homepage.ts`**

Replace the placeholder with the real implementation:

```typescript
// frontend/pages/homepage.ts
// Fetches experiment count from /api/stats and updates the homepage display

import { getStats } from '../api/client'

async function init(): Promise<void> {
  const countEl = document.getElementById('experiment-count')
  if (!countEl) return

  try {
    const stats = await getStats()
    if (stats.total_experiments_formatted) {
      countEl.textContent = stats.total_experiments_formatted
    }
  } catch (err) {
    // If the API call fails, keep the server-rendered count
    console.warn('Failed to fetch stats:', err)
  }
}

document.addEventListener('DOMContentLoaded', init)
```

- [ ] **Step 3: Build the TypeScript**

```bash
cd /Users/inutano/repos/chip-atlas && node esbuild.config.mjs
```

**Expected:** Build succeeds, `public/js/homepage.js` is created. Output should show the built file with its size.

Verify:
```bash
test -f /Users/inutano/repos/chip-atlas/public/js/homepage.js && echo "OK: homepage.js exists" || echo "FAIL"
```

- [ ] **Step 4: Test the homepage**

```bash
cd /Users/inutano/repos/chip-atlas && \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
ruby -e "
  require 'bundler/setup'
  require 'rack/test'
  require_relative 'app'
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  get '/'
  puts \"Status: #{last_response.status}\"
  puts \"Has ChIP-Atlas: #{last_response.body.include?('ChIP-Atlas')}\"
  puts \"Has Bootstrap 5: #{last_response.body.include?('bootstrap5.min.css')}\"
  puts \"Has homepage.js: #{last_response.body.include?('homepage.js')}\"
  puts \"Has feature cards: #{last_response.body.include?('feature-card')}\"
  puts \"Has Peak Browser: #{last_response.body.include?('Peak Browser')}\"
  puts \"Has navbar: #{last_response.body.include?('navbar-expand-lg')}\"
"
```

**Expected output:**
```
Status: 200
Has ChIP-Atlas: true
Has Bootstrap 5: true
Has homepage.js: true
Has feature cards: true
Has Peak Browser: true
Has navbar: true
```

- [ ] **Step 5: Commit**

```
Convert homepage to ERB with Bootstrap 5 cards and stats fetch

Six feature cards (Bootstrap 5 card component) replace the Bootstrap 3
jumbotrons. TypeScript homepage.ts fetches /api/stats to update the
experiment count display. Updates section rendered from updates.markdown.
```

---

## Final Verification

After all 6 tasks are complete, run these checks:

```bash
cd /Users/inutano/repos/chip-atlas

# 1. TypeScript compiles cleanly
npx tsc --project frontend/tsconfig.json --noEmit && echo "TS: OK" || echo "TS: FAIL"

# 2. esbuild produces output
node esbuild.config.mjs && echo "Build: OK" || echo "Build: FAIL"

# 3. All pages return 200
PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
ruby -e "
  require 'bundler/setup'
  require 'rack/test'
  require_relative 'app'
  include Rack::Test::Methods
  def app; ChipAtlasApp; end
  ['/', '/publications', '/agents', '/demo'].each do |path|
    get path
    puts \"#{path}: #{last_response.status}\"
  end
  get '/this-does-not-exist-at-all'
  puts \"404: #{last_response.status}\"
"
```

**Expected:**
```
TS: OK
Build: OK
/: 200
/publications: 200
/agents: 200
/demo: 200
404: 404
```

All existing HAML-based pages (peak_browser, enrichment_analysis, etc.) continue to work unchanged since their routes still call `erb :template_name` which will NOT find `.haml` files -- but those routes already use `erb` in the current code. Wait: looking at the current `routes/pages.rb`, ALL routes already call `erb :template_name`. This means they will look for `.erb` files. Since we are only creating `.erb` files for the pages in this plan (about, publications, agents, demo, not_found), the other pages (peak_browser, search, experiment, etc.) will fail because they call `erb :peak_browser` but `peak_browser.erb` does not exist.

**Critical fix:** The other pages that are NOT being converted in this plan need to remain on HAML. Update their routes to explicitly call `haml :template_name` instead of `erb :template_name`.

This is handled in Task 4 Step 4 (modify routes/pages.rb). Here are the routes that must be changed to `haml`:

```ruby
# In routes/pages.rb, change these routes from erb to haml:

        app.get '/peak_browser' do
          load_analysis_settings
          haml :peak_browser
        end

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
          haml :experiment
        end

        app.get '/colo' do
          @index_all_genome = ChipAtlas::Experiment.cached_index_all_genome
          @list_of_genome   = ChipAtlas::Experiment.list_of_genome
          haml :colo
        end

        app.get '/colo_result' do
          @data_url = params[:data_url]
          halt 400 unless @data_url&.start_with?('https://chip-atlas.dbcls.jp/')
          haml :colo_result
        end

        app.get '/target_genes' do
          @index_all_genome = ChipAtlas::Experiment.cached_index_all_genome
          @list_of_genome   = ChipAtlas::Experiment.list_of_genome
          haml :target_genes
        end

        app.get '/target_genes_result' do
          @data_url = params[:data_url]
          halt 400 unless @data_url&.start_with?('https://chip-atlas.dbcls.jp/')
          haml :target_genes_result
        end

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

        app.get '/enrichment_analysis_result' do
          haml :enrichment_analysis_result
        end

        app.get '/diff_analysis' do
          load_analysis_settings
          haml :diff_analysis
        end

        app.get '/diff_analysis_result' do
          haml :diff_analysis_result
        end

        app.get '/search' do
          haml :search
        end
```

**Wait -- re-reading the current code more carefully:** The current `routes/pages.rb` already uses `erb :about`, `erb :publications`, etc. for ALL routes. But the views are `.haml` files. How does this work?

Looking at the current code again: `erb :about` would look for `about.erb`. It does NOT exist. Sinatra would raise a template-not-found error. So either:
1. The app is not actually running with these routes (but it is, per the smoke tests), or
2. Sinatra's tilt integration falls back to other engines when the preferred engine's template is not found.

Actually, re-reading Sinatra docs: `erb :about` specifically looks for `views/about.erb`. It does NOT fall back to HAML. But the current code uses `erb :about` and only `about.haml` exists...

Let me re-check. The Gemfile does NOT include `haml` or `tilt` as explicit dependencies. Sinatra depends on tilt. Tilt supports multiple engines. Actually, the key insight: **Sinatra's `erb` method will only render ERB templates.** If `about.erb` doesn't exist, it raises `Errno::ENOENT`.

But wait -- the current production app works. Let me look more carefully at the actual routes. The current `routes/pages.rb` has `erb :about`. The file `about.haml` exists but `about.erb` does NOT. This means either:

1. The HAML files ARE complete HTML documents (they are -- I can see the `!!! 5` doctype), so they don't need a layout.
2. The production deploy might have a different version of `routes/pages.rb`.

Actually I think the answer is simpler: looking at the Gemfile, there is no `haml` gem. But tilt (via sinatra) can handle haml if the gem is installed. Without the haml gem, `haml :about` would fail. So the current `erb :about` is correct IF `about.erb` exists... but it doesn't.

Hmm. Let me reconsider. Looking at the git history -- the most recent commit message is "Fix FTS search queries crashing on AR 8.0.3 bind param casting". This is the backend rebuild branch. The HAML files are legacy from before the rebuild. The current `routes/pages.rb` calls `erb :template` but the `.erb` files don't exist yet. **The page routes are currently broken by design** -- the backend rebuild (Plan 1) created the API routes and page route stubs that call `erb`, with the intention that this frontend plan creates the actual `.erb` files.

This simplifies everything. We don't need to worry about HAML fallback. The current `routes/pages.rb` already calls `erb` for everything. We just need to create the `.erb` files. Pages we don't convert in this plan will remain broken until Plans 2 and 3 create their ERB files.

**Revised approach for Task 4 Step 4:** We do NOT need to change any routes to `haml`. The routes already call `erb`. We only need to add `@page_js` to the homepage route. For pages not converted in this plan, they will return 500 (template not found) -- that's expected and will be fixed in Plans 2 and 3.

This is reflected in the plan above. Task 4 Step 4 only modifies the homepage route to add `@page_js`. The static page routes remain as-is since `@active_menu` is set in the ERB templates.

---

## Dependencies Between Tasks

```
Task 1 (esbuild) ──────────────────────────────────────────┐
Task 2 (Bootstrap 5) ─────────────────────────────────────┐│
Task 3 (API client) ─── depends on Task 1 (npm install)  ││
Task 4 (Layout) ──────── depends on Task 2 (CSS files)   ││
Task 5 (Static pages) ── depends on Task 4 (layout.erb)  ││
Task 6 (Homepage) ────── depends on Task 3, 4, 5         ┘┘
```

**Recommended execution order:** Tasks 1 and 2 can run in parallel. Task 3 depends on Task 1 (needs `npm install` for `tsc`). Task 4 depends on Task 2 (references `bootstrap5.min.css`). Task 5 depends on Task 4 (inherits layout). Task 6 depends on Tasks 3+4+5 (uses API client, layout, and needs static pages working).

**Parallelism opportunity:** Tasks 1+2 in parallel, then Tasks 3+4 in parallel, then Task 5, then Task 6.
