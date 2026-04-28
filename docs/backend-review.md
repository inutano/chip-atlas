# Backend Code Review Notes

Review of the sengu backend before starting frontend development.

---

## config/puma.rb

Production web server configuration.

- **Concurrency**: 2 workers x 5 threads = 10 concurrent requests
- **`preload_app!`**: Loads app once before forking workers (copy-on-write memory savings)
- **`before_fork`**: Disconnects DB so each forked worker gets its own SQLite connection
- **`worker_timeout 60`**: Allows time for slow data proxy requests (DataProxy has 30s read timeout)
- **Logging**: Files in production (`log/puma.stdout.log`), stdout in development
- **Defaults**: Production env, port 9292 — override with `RACK_ENV`, `PORT`, `WEB_CONCURRENCY`, `MAX_THREADS`
- **Note**: No explicit `on_worker_boot` DB reconnect — Sequel handles this lazily, fine for file-based SQLite

## app.rb

Main application entry point.

- **Boot order**: bundler/setup → stdlib → sinatra → lib/db → lib/chip_atlas → middleware → routes
- **Middleware**: `ChipAtlas::JsonBodyParser` parses POST JSON bodies into `env['parsed_body']`
- **ERB config**: `escape_html: true` for XSS protection by default
- **Route registration**: Health → Api → Jobs → Pages (Pages last, likely has catch-all)
- **Helpers**:
  - `json_response(data)` — sets content-type, generates JSON
  - `parsed_json` — retrieves parsed body from middleware, halts 400 if missing, logs activity
  - `log_activity(action, data)` — TSV format: ISO8601 + IP + action + optional JSON data
- **Logging**: Daily-rotated `log/access_log`, custom formatter (raw message, no log level prefix)
- **Production**: `host_authorization` restricts to `*.chip-atlas.org`
- **No `before` filter, no data preloading** — clean instant boot
- **Decision**: Use ERB for new frontend (stdlib, zero deps, 10-year stability). Keep templates dumb — logic in API or TypeScript layer.

## lib/db.rb

Database connection and SQLite tuning.

- **Guard**: `unless defined?(DB)` prevents double-init (safe for test suite's in-memory DB)
- **Default**: `sqlite://database.sqlite`, overridable via `DATABASE_URL` env var
- **`pool_timeout: 300`**: 5 min wait for connection from pool (generous for 10 concurrent threads)
- **SQLite PRAGMAs**:
  - `WAL` — concurrent reads during writes
  - `synchronous=NORMAL` — speed/durability balance
  - `cache_size=-64000` — 64MB page cache
  - `mmap_size=256MB` — memory-mapped I/O for fast reads
- **rescue** — graceful fallback for in-memory test DB
- **`Sequel.extension :migration`** — loaded here for rake task access

## lib/chip_atlas.rb

Module loader. Requires 6 models + serializers + 6 services. `VERSION = '2.0.0'`. No logic.

## lib/serializers.rb

Single method: `classification_item(id, count)` → `{id:, label:, count:}`. Used by faceted dropdown API endpoints. Label defaults to id value.

## lib/models/experiment.rb

Core model — constants, faceted queries, data loading. ~240 lines.

- **Constants**: `GENOMES` (7 assemblies), `GENOME_ORDER` (sort order), `EXPERIMENT_TYPES` (10 types incl. CUT&Tag/CUT&RUN)
- **Caching**: `cached_index_all_genome` with 1hr TTL — heavy query, 2 SQL GROUP BYs across all genomes
- **Faceted queries**: `experiment_types`, `sample_types`, `chip_antigen`, `cell_type` — all use SQL aggregation, return `{id, label, count}` arrays
- **`record_by_experiment_id`**: Returns all matching rows sorted by GENOME_ORDER
- **`total_number_of_reads`**: Parses CSV read_info in SQL with SUBSTR/INSTR/CAST — no Ruby overhead
- **`load_from_file`**: Transaction-wrapped, 5K batch inserts, genome-filtered
- **`stats`**: New endpoint — total experiments + breakdowns by genome and track_class
- **TODO**: `get_subclass` references `'All antigens'` — dead code, tracks are now heterogeneous. Remove.
- **TODO**: `'undefined'` string checks (lines 95, 112, 130) — valid progressive filtering logic (cascading dropdowns: user selects genome → track_class before cell_type_class is chosen). New frontend should omit param or send nil; backend should check `nil` instead of `'undefined'`.

## lib/models/experiment_search.rb

FTS5 full-text search over experiments. ~95 lines.

- **FTS5 columns**: experiment_id, sra_id, geo_id, genome, track_class, track_subclass, cell_type_class, cell_type_subclass, title, attributes
- **`search`**: Parameterized FTS5 MATCH query, `COUNT(*) OVER()` for total count, optional genome filter, limit/offset pagination
- **`fts5_sanitize`**: Strips special chars (`"'()*^{}:`), wraps each token in quotes — prevents FTS5 syntax errors
- **`gsm_to_srx`**: GEO→SRA ID lookup for `/view` page redirect
- **`load_from_json`**: Transaction-wrapped, 500-row batches, genome filtering (Array→single value), `DB.literal` for escaping (FTS5 needs raw INSERT SQL)
- **Note**: Genome equality filter (`genome = ?`) now works correctly after cleaning combined strings to single values

## lib/models/bedfile.rb

BED file lookup by experimental condition. ~90 lines.

- **`filesearch`**: Queries by genome, track_class, track_subclass, cell_type_class, cell_type_subclass, qval. `.limit(2)` — only needs 0, 1, or >1 results.
- **`get_filename` / `get_trackname`**: Wrappers that raise `NotFound` if not exactly 1 result
- **`qval_range`**: Distinct qval values, excludes Bisulfite-Seq and Annotation tracks
- **Defaults**: track_subclass and cell_type_subclass default to `'-'` when nil (means "all")

## lib/models/bedsize.rb

Peak count statistics. ~55 lines.

- **`dump`**: Flat hash with composite string keys: `"genome,track_class,cell_type_class,qval" → number_of_lines`
- Frontend parses these keys for display

## lib/models/analysis.rb

Colo and target genes analysis indexes. ~85 lines.

- **`colo_result_by_genome(genome)`**: Builds bidirectional index — track→[cell_types] and cell_type→[tracks] — from comma-separated `cell_list` column
- **`target_genes_result`**: Groups tracks by genome where `target_genes: true`
- **`TARGET_GENES_DISTANCES`**: Constant for distance options (1kb, 5kb, 10kb)

## lib/models/sra_cache.rb

NCBI SRA metadata cache. ~40 lines.

- **TTL**: 30 days
- **`get`**: Returns parsed JSON or nil if expired/missing
- **`set`**: Atomic upsert via `insert_conflict(target: :experiment_id)`
- **`clear_expired`**: Deletes rows past TTL
- Fills on demand via SraService when experiment detail page is viewed

## lib/services/location_service.rb

URL construction for data access (archives, IGV, colo, target genes). ~88 lines.

- **`ARCHIVE_BASE`**: `https://chip-atlas.dbcls.jp/data`
- **`archive_url`**: BED file URL, special case for Annotation tracks (different path, "All cell types" override)
- **`igv_browsing_url`**: IGV desktop app load URL (default localhost:60151)
- **Colo URLs**: `{track}.{cell_type}.json/tsv`, `{cell_type}.gml` — under `/{genome}/colo/`
- **Target genes URLs**: `{track}.{distance}.json/tsv` — under `/{genome}/target/`
- **Encoding**: `URI.encode_www_form_component` for user-provided track/cell_type values
- **`encoded_cell_type`**: Replaces spaces with underscores to match data server file naming
- **Graceful**: `bed_url`/`annotation_url` rescue `Bedfile::NotFound` → nil
- **Note**: IGV URL query params not fully encoded — low risk (controlled data), but not perfect

## lib/services/data_proxy.rb

Proxies data from chip-atlas.dbcls.jp to clients. ~30 lines.

- **SSRF protection**: Exact host match (`uri.host == DATA_HOST`)
- **Timeouts**: 10s open, 30s read
- **Always SSL**
- **Returns**: Raw response body string or nil on any error
- **Note**: Named `fetch` — returns raw response body (JSON, TSV, GML).

## lib/services/service_monitor.rb

Health checks for external services with cached status. ~95 lines.

- **Services**: `data_server` (chip-atlas.dbcls.jp), `wabi` (DDBJ NIG), `wes` (Sapporo at ea.chip-atlas.org)
- **`CHECK_INTERVAL`**: 60s — cached status, prevents hammering external services
- **State**: Module-level `@statuses` and `@checked_at` — per-worker process
- **Timeouts**: Outer `Timeout.timeout(8)`, inner 5s open + 5s read
- **Method**: HEAD requests, `response.code.to_i < 500` means alive
- **`all_statuses`**: Maps raw service status into user-facing feature availability
- **Feature mapping**: peak_browser/colo/target_genes need data_server; enrichment_analysis tries WABI then WES with `'ok (backup)'`; diff_analysis needs WABI only
- **Tiered checking** (commit `492579f`): Always check data_server and wabi; check wes only when wabi is down. WES is on-demand backup, only launched during scheduled WABI downtime. Cold start: ~16s instead of ~24s.
- **Concerns**:
  - Per-worker caching → 2x checks per minute (acceptable)
  - Thread-safety: not atomic, could cause duplicate HTTP requests in same worker (not a bug)
  - No way to force-refresh (60s lag when service recovers)

## lib/services/wabi_service.rb

WABI (DDBJ NIG) compute backend client. ~70 lines.

- **`ENDPOINT`**: `https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/`
- **`submit_job`**: `Net::HTTP.post_form`, parses `requestId` from text response
- **`job_finished?`**: HEAD request to result URL, returns true/false/nil (nil on error → treated as "running" by caller)
- **`fetch_log`**: GET log endpoint, returns body or nil
- **TODO**: `endpoint_available?` and `check_endpoint` are dead code — `ComputeRouter` uses `ServiceMonitor` instead. Remove.
- **Note**: `submit_job` has no explicit timeout (uses Ruby defaults: 60s). Acceptable for long-running job submissions.

## lib/services/sapporo_service.rb

GA4GH WES client for Sapporo backup compute. ~107 lines.

- **`ENDPOINT`**: `https://ea.chip-atlas.org`
- **`submit_job`**: POST to `/runs` with workflow params as JSON in form data, returns `run_id`
- **`job_status`**: Maps WES states (COMPLETE, EXECUTOR_ERROR, RUNNING, etc.) to internal strings
- **`result_url`/`result_tsv_url`**: Pure URL construction — results hosted on chip-atlas.dbcls.jp, not the WES endpoint
- **`fetch_log`**: Digs into WES `run_log` for stderr, fallback to stdout
- **TODO**: `endpoint_available?` and `check_endpoint` are dead code — same as WabiService, remove.

## lib/services/compute_router.rb

Backend failover routing for analysis jobs. ~67 lines. Strategy pattern.

- **Failover**: WABI (primary) → WES (enrichment only) → unavailable. Diff analysis has no backup.
- **Methods**: `available_backend`, `submit`, `status`, `result_urls`, `log` — all dispatch to correct service via `case backend`
- **Stateless**: Pure dispatch, no caching — relies on ServiceMonitor for availability
- **Fail-fast**: `submit` checks availability before attempting HTTP calls
- **Note**: WABI status is binary (finished/running), WES is richer (finished/running/error/canceled). Callers should handle all values.

## lib/services/sra_service.rb

NCBI SRA metadata fetcher for experiment detail page. ~113 lines. Instance-based (only service using `class` not `module`).

- **Cache-first**: Checks `SraCache` (30-day TTL) before hitting NCBI
- **NCBI flow**: `esearch` (experiment_id → UID, JSON) → `efetch` (UID → full metadata, XML)
- **REXML**: Pure Ruby XML parser — no C extension dependency
- **`get_uid`**: Only accepts exactly 1 result — defensive against ambiguous matches
- **`parse_experiment`**: Extracts library description, platform info, layout from SRA XML
- **`error_metadata`**: Returns full-shaped hash with error messages — frontend always gets expected structure
- **Timeouts**: 10s open, 15s read
- **Note**: No NCBI API key — rate-limited to 3 req/s. Cache mitigates this; only fresh IDs trigger NCBI calls.

## routes/health.rb

Health and status endpoints. ~35 lines.

- **`/health`**: DB connection test + experiments count. Returns 200/503. For load balancers.
- **`/status`**: ServiceMonitor.all_statuses with 30s cache. For frontend alerts.

## routes/api.rb

Main API routes — 30 endpoints. ~230 lines.

- **Sections**: Classification (7) → Data (5) → Analysis indexes (3) → URL generation (4) → Data proxy (4) → Downloads (2) → Internal (1)
- **`condition_from_params`**: Helper bridges query params to LocationService, `.compact` strips nil
- **Validation**: Consistent `halt 400` with JSON error messages
- **Caching**: Stable data cached (genomes 1d, genome_index/qval_range/bed_sizes/stats 1h, target_genes_distances 1d)
- **SSRF**: `allowed_remote_url?` with exact host match (fixed subdomain bypass)
- **Search**: Limit clamped 1-100, offset defaults to 0, activity logged
- **TODO**: `/api/subclasses` — no param validation, calls deprecated `get_subclass` with `'All antigens'`. Likely dead code for new frontend — consider removing.
- **TODO**: `/api/colo_index` has no caching — does full table scan per genome. Consider adding cache_control.
- **Note**: Download endpoints load full file into memory before sending. Streaming would reduce memory spikes for large files, but acceptable for now.

## routes/jobs.rb

Job submission and monitoring proxy. ~112 lines. No job state on app server.

- **Endpoints**: `/jobs/available`, `/jobs/submit`, `/jobs/:id/status`, `/jobs/:id/result`, `/jobs/:id/log`, `/jobs/estimated_time`
- **Validation**: `validated_job_id` (regex `[\w\-]+`), `validated_backend` (whitelist wabi/wes)
- **Circuit breaker**: `backend_available?` checks ServiceMonitor before every call — halts 503 with `retry: false`
- **Pure proxy**: No DB, no job tracking — delegates everything to ComputeRouter
- **Estimated time**: Logarithmic regression (DMR) and linear (DiffBind), +600s buffer, handles infinity
- **Note**: `/jobs/:id/log` returns plain text 503 while other endpoints return JSON — minor inconsistency

## routes/pages.rb

HTML page routes. ~115 lines. Currently renders HAML, will be ERB.

- **Pages**: about(homepage), peak_browser, view(experiment detail), colo, colo_result, target_genes, target_genes_result, enrichment_analysis (GET+POST), enrichment_analysis_result, diff_analysis, diff_analysis_result, search, publications, agents, demo, 404
- **`load_analysis_settings`**: Shared helper — loads genome index, genome list, qval range into instance variables
- **`/view`**: GSM→SRX redirect, id validation, activity logging, SRA metadata fetch
- **URL validation**: colo_result/target_genes_result only accept `https://chip-atlas.dbcls.jp/` prefix
- **TODO**: `/view` — `params[:id].upcase` crashes if id param missing. Add guard.
- **Frontend decisions for rebuild**:
  - colo_result/target_genes_result will use API proxy endpoints instead of passing data_url to template
  - POST /enrichment_analysis form submission → replaced by /jobs/submit API + client-side handling
  - Instance variables vs API fetch: prefer API fetch from TypeScript, keep templates minimal
  - Static pages (search, publications, agents, demo, result pages) need no server data — could be plain ERB shells

## lib/middleware/json_body_parser.rb

Rack middleware for JSON POST body parsing. ~35 lines.

- Only parses POST + `application/json` content type
- `request.body.rewind` preserves body for downstream readers
- Returns 400 with `{"error":"Invalid JSON"}` before routes on parse failure
- Stores result in `env['parsed_body']` — accessed via `parsed_json` helper

## db/migrations/001_create_schema.rb

Database schema. 5 tables + 1 FTS5 virtual table.

- **experiments**: Composite indexes on `[genome, track_class]` and `[genome, track_class, cell_type_class]` — match cascading dropdown queries
- **bedfiles**: 6-column composite index `idx_bedfiles_lookup` — matches `filesearch` query
- **bedsizes**: 4-column composite `idx_bedsizes_lookup`
- **analyses**: Indexes on track, genome, target_genes
- **sra_cache**: Unique constraint on experiment_id — supports upsert
- **experiments_fts**: FTS5 virtual table with 10 columns
- **Note**: No unique constraint on `experiments.experiment_id` — intentional (was multi-genome), but now one row per experiment after old assembly cleanup

## Gemfile

7 production gems, 3 dev/test. Zero C extensions beyond sqlite3.

- sinatra, puma, sequel, sqlite3, kramdown, rexml, rake
- Dev: webrick, minitest, rack-test

## Dockerfile

Simple single-stage build. `ruby:3.2.2-slim`.

- **TODO**: Ruby version 3.2.2 — dev machine runs 4.0.1. Bump to match deployment target.
- **TODO**: No `.dockerignore` — copies database.sqlite (965MB), .git, tests, docs. Add one.
- **TODO**: `libffi-dev` likely no longer needed (was for Nokogiri). Remove.
- **Note**: No multi-stage build — build-essential stays in final image. Minor for single-server deploy.

## test/test_helper.rb

Test infrastructure. In-memory SQLite + seed helpers.

- **In-memory DB** (`sqlite:/`) — fast, isolated, no file cleanup
- **Runs migrations** on boot — schema always current
- **Seed helpers**: experiments (4 rows, 2 genomes), bedfiles (2), analyses (2), bedsizes (2)
- **Teardown**: Deletes all tables + FTS5 — no state leakage

## Test coverage

7 test files, 50 tests, 129 assertions. All passing.

| File | Tests |
|------|-------|
| models/experiment_test.rb | Genome list, experiment types, record lookup, read counts |
| models/experiment_search_test.rb | FTS5 search, genome filter, pagination |
| models/bedfile_test.rb | File search, qval range |
| routes/api_test.rb | Classification, data, stats, distance endpoints |
| routes/health_test.rb | Health check, status endpoint |
| serializers_test.rb | classification_item formatting |
| services/location_service_test.rb | URL generation for archives, IGV, colo, target genes |

**Missing coverage** (not blocking, but valuable):
- models: analysis, bedsize, sra_cache
- services: compute_router (failover logic), service_monitor
- routes: jobs (validation, circuit breaker), pages (rendering, redirects)
- middleware: json_body_parser

## config.ru

Standard Rack entry point. 2 lines: `require_relative 'app'` + `run ChipAtlasApp`.

## Rakefile

Task runner. `db:migrate`, `db:reset` (handles FTS5 virtual table), auto-loads from `lib/tasks/**/*.rake`.

---

## Summary of TODOs

| Priority | Item | File |
|----------|------|------|
| Fix | `get_subclass` references deprecated `'All antigens'` — dead code, remove | experiment.rb |
| Fix | `'undefined'` string checks → change to nil checks when new frontend is ready | experiment.rb |
| Fix | `/view` crashes if `id` param missing — add guard | routes/pages.rb |
| Fix | Dead code: `endpoint_available?` / `check_endpoint` in both services | wabi_service.rb, sapporo_service.rb |
| Fix | Dockerfile: bump Ruby version, add `.dockerignore`, remove `libffi-dev` | Dockerfile |
| Consider | `/api/colo_index` — no caching on full table scan | routes/api.rb |
| Done | `DataProxy.fetch_json` renamed to `fetch` | data_proxy.rb |
| Consider | Add test coverage for analysis, bedsize, sra_cache, jobs, pages | test/ |
| Defer | Remove old static JSON files (ExperimentList*.json) when new frontend replaces search | public/ |
