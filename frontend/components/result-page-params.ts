// frontend/components/result-page-params.ts
// Reads the query string both analysis result pages arrive with.
//
// Production redirects to `/…_result?id=…&title=…&calcm=…` after a
// submission, carrying the analysis title and the run-time estimate forward
// so the result page can show them without asking the backend (neither is
// anything WABI stores). It names the backend only on the Enrichment
// Analysis page, as `api=wabi` (its Diff Analysis redirect carries no backend
// hint at all -- WABI was its only backend, ever). This app routes between
// WABI and a WES service, so it needs to know which one names the job -- it
// reads its own `backend=` first, falls back to translating production's
// `api=`, and otherwise defaults to `wabi`, production's only backend and the
// one every legacy URL implicitly meant.
//
// `id` is the only parameter this cannot do without: production's bookmarked
// result URLs, and its own redirects, both always carried it, and there is no
// backend-neutral default for "which job".
//
// Split out of the two near-identical page entry points so the parsing has one
// home and a test can reach it without a DOM (frontend/pages entry points each
// duplicate small helpers rather than share a module — see colo-result.ts's
// header — but this one is the page's whole input contract, and getting it
// wrong silently strands the user on an error state).

export interface ResultPageParams {
  jobId: string
  backend: string
  title: string
  calcm: string
}

/**
 * Resolves which backend a legacy or current result URL names.
 *
 * `backend=` (this app's own redirects, see diff-analysis.ts /
 * enrichment-analysis.ts) is authoritative when present. Otherwise this reads
 * production's `api=`: its literal value was always `wabi` when present at
 * all (Enrichment Analysis's only redirect shape), so that maps to `'wabi'`
 * and any other non-empty value -- a host name, a future protocol -- maps to
 * `'wes'`, the only other backend this app knows. A bare `?id=…` (production's
 * Diff Analysis shape, which never named a backend) defaults to `'wabi'`,
 * since WABI was production's only backend for either analysis.
 */
function resolveBackend(params: URLSearchParams): string {
  const backend = params.get('backend')
  if (backend) return backend
  const api = params.get('api')
  if (api) return api === 'wabi' ? 'wabi' : 'wes'
  return 'wabi'
}

/**
 * Returns null when `id` is absent or empty — the page then shows its error
 * state instead of polling a job that was never named.
 *
 * `title` and `calcm` are optional: a URL someone bookmarked before those were
 * carried, or typed by hand, still tracks the job. They default to empty, and
 * JobTracker renders an em dash for each.
 */
export function readResultPageParams(search: string): ResultPageParams | null {
  const params = new URLSearchParams(search)
  const jobId = params.get('id')
  if (!jobId) return null
  return {
    jobId,
    backend: resolveBackend(params),
    title: params.get('title') ?? '',
    calcm: params.get('calcm') ?? '',
  }
}
