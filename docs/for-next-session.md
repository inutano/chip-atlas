# Session Handoff — Frontend Rebuild

**Date:** 2026-05-13
**Branch:** `sengu`
**Last commit:** `0140da2`

---

## What's Done

### Backend (Phase 1) — COMPLETE
- All models ported to Sequel (experiment, experiment_search, bedfile, bedsize, analysis, sra_cache)
- All services built (location_service, wabi_service, sapporo_service, compute_router, data_proxy, service_monitor, sra_service)
- All routes working (api, jobs, pages, health — 30+ endpoints)
- 50 tests passing, 129 assertions
- Old genome assemblies removed (hg19, mm9, dm3, ce10)
- Runs model removed (ID conversion outsourced to togoid.dbcls.jp)
- SSRF fix, dead code cleanup, Dockerfile updated
- Backend review notes in `docs/backend-review.md`

### Frontend Design — COMPLETE
- Design spec: `docs/superpowers/specs/2026-05-12-frontend-rebuild-design.md`
- Main design spec updated: `docs/superpowers/specs/2026-04-04-shikinen-sengu-design.md`
- Result JSON spec for pipeline v2: `docs/result-json-spec.md`

### Decisions Made
- **Bootstrap 5** (self-hosted, vendored) — upgrade from Bootstrap 3
- **TypeScript** (esbuild-compiled) — replaces jQuery
- **ERB templates** — replaces HAML, Ruby stdlib
- **Bootstrap Icons** (SVG) — replaces Font Awesome
- **No CDN, no npm CSS** — all assets local
- **Autocomplete**: substring matching (improvement over old prefix-only)
- **FacetFilter**: bidirectional count updates
- **Colo/Target Genes results**: in-app JSON rendering (not redirect to external HTML)
- **Mobile-first**: responsive testing required per page

---

## What's Next

### Immediate: Execute Plan 1 — Frontend Foundation
**Plan file:** `docs/superpowers/plans/2026-05-13-frontend-foundation.md`

6 tasks:
1. esbuild + TypeScript setup (package.json, tsconfig, build config)
2. Bootstrap 5.3.3 vendored + style.css
3. TypeScript API client (typed fetch wrappers for all endpoints)
4. ERB layout (layout.erb + navbar + footer)
5. Static pages (publications, agents, demo, 404)
6. Homepage (about.erb + stats fetch)

**How to execute:** Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to work through the plan task by task.

### After Plan 1: Write + Execute Plan 2 — Shared Components + Simple Pages
- 4 shared components: GenomeTabs, FacetFilter, Autocomplete, JobTracker
- Search page (server-side pagination replaces 200MB JSON + DataTables)
- Experiment detail page (/view)

### After Plan 2: Write + Execute Plan 3 — Analysis Pages
- Peak Browser (flagship — uses all components)
- Enrichment Analysis (most complex — file upload, validation, job submission)
- Diff Analysis
- Target Genes (setup + result)
- Colo (setup + result)
- Enrichment/Diff result pages (JobTracker)

### Remaining Backend TODOs (low priority)
- Add caching to `/api/colo_index` (one-line fix)
- Add test coverage for analysis model, jobs routes, sra_cache
- Remove old static JSON files after search page is rebuilt
- Clean up `'undefined'` string checks after new frontend is ready

---

## Key Files

| File | Purpose |
|------|---------|
| `docs/superpowers/specs/2026-05-12-frontend-rebuild-design.md` | Frontend design spec |
| `docs/superpowers/specs/2026-04-04-shikinen-sengu-design.md` | Overall shikinen-sengu spec |
| `docs/superpowers/plans/2026-05-13-frontend-foundation.md` | Plan 1 (ready to execute) |
| `docs/result-json-spec.md` | JSON formats for pipeline v2 |
| `docs/backend-review.md` | Backend code review notes + TODO table |
