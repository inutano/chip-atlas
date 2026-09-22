// frontend/components/result-page-params.ts
// Reads the query string both analysis result pages arrive with.
//
// Production redirects to `?id=…&api=wabi&title=…&calcm=…` after a submission,
// carrying the analysis title and the run-time estimate forward so the result
// page can show them without asking the backend (neither is anything WABI
// stores). This app names the backend `backend=` rather than `api=`, since it
// routes between WABI and a WES service and the value is the backend, not a
// protocol — otherwise the shape is production's.
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
 * Returns null when the two required parameters are absent — the page then
 * shows its error state instead of polling a job that was never named.
 *
 * `title` and `calcm` are optional: a URL someone bookmarked before those were
 * carried, or typed by hand, still tracks the job. They default to empty, and
 * JobTracker renders an em dash for each.
 */
export function readResultPageParams(search: string): ResultPageParams | null {
  const params = new URLSearchParams(search)
  const jobId = params.get('id')
  const backend = params.get('backend')
  if (!jobId || !backend) return null
  return {
    jobId,
    backend,
    title: params.get('title') ?? '',
    calcm: params.get('calcm') ?? '',
  }
}
