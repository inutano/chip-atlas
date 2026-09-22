// frontend/components/job-tracker.ts
// Fills in the job-info table on the two analysis result pages, polls the
// job's status, reveals the result links when it finishes, and streams the
// execution log.
//
// The markup is static, in views/enrichment_analysis_result.erb and
// views/diff_analysis_result.erb, the way production's two result pages have
// it — this only writes into it. The two pages differ in exactly one place,
// the result-link rows (an enrichment job has an HTML table plus a TSV of the
// same rows; a diff job has a zip archive), and that difference lives in the
// ERB: each result anchor carries `data-result-key`, naming the key it wants
// out of GET /jobs/:id/result. Nothing here needs to know which page it is on.

import { getJobStatus, getJobResult, getJobLog, type JobResult } from '../api/client'

const POLL_INTERVAL_MS = 10_000
const CLOCK_INTERVAL_MS = 1000

const FINISHED_STATUSES = new Set(['finished', 'completed', 'success'])
const FAILED_STATUSES = new Set(['error', 'failed', 'backend_unavailable'])

export type JobType = 'enrichment_analysis' | 'diff_analysis'

export interface JobTrackerOptions {
  jobId: string
  backend: string
  jobType: JobType
  /** The analysis title the user typed, carried in the URL from the submit page. */
  title: string
  /** The estimate the submit page showed, e.g. "13 mins" or "1.6 hr". */
  calcm: string
}

const EM_DASH = '—'

// ===== Pure helpers (exported for frontend/components/job-tracker.test.ts) =====

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function pad(n: number): string {
  return n.toString().padStart(2, '0')
}

/**
 * Production's timestamp format: `HH:MM:SS (Mon-DD-YYYY)`, given once in the
 * viewer's own timezone and once in UTC.
 *
 * Production builds this by splitting `Date.prototype.toString()` on spaces
 * and indexing the pieces. That output is not specified beyond "implementation
 * defined", so the same code can produce a different string on a different
 * engine; this composes the same visible format from the date's own fields
 * instead.
 */
export function formatStamp(date: Date): string {
  if (Number.isNaN(date.getTime())) return EM_DASH
  const local = `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}` +
    ` (${MONTHS[date.getMonth()]}-${pad(date.getDate())}-${date.getFullYear()})`
  const utc = `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}` +
    ` (${MONTHS[date.getUTCMonth()]}-${pad(date.getUTCDate())}-${date.getUTCFullYear()})`
  return `${local} / UTC: ${utc}`
}

/**
 * When the job was submitted, read out of the WABI request ID itself.
 *
 * WABI mints IDs as `wabi_chipatlas_YYYY-MMDD-HHMM-SS-<n>-<n>`, stamped in
 * DDBJ's own timezone (JST). Two finished jobs confirm the reading against
 * their own execution logs: `…_2026-0922-1049-51-…` logged
 * `Start: 2026-09-22T10:50:21+09:00`, and `…_2026-0922-0427-11-…` logged
 * `Start: 2026-09-22T04:27:37+09:00` — 30 and 26 seconds after the stamp, as
 * a queue hand-off should be.
 *
 * Production instead shows `new Date()` at page load, which is only the
 * submission time on the one render that follows the redirect: reopen the URL
 * an hour later — which the page itself invites, telling you it stays valid
 * for a week — and it reports the time you reopened it as the time you
 * submitted. Returns null for an ID that is not WABI's shape, and the caller
 * then falls back to production's behaviour.
 */
export function parseWabiSubmitTime(jobId: string): Date | null {
  const m = /^wabi_chipatlas_(\d{4})-(\d{2})(\d{2})-(\d{2})(\d{2})-(\d{2})-/.exec(jobId)
  if (!m) return null
  const [, year, month, day, hour, minute, second] = m
  const date = new Date(`${year}-${month}-${day}T${hour}:${minute}:${second}+09:00`)
  return Number.isNaN(date.getTime()) ? null : date
}

/**
 * Minutes of compute implied by the estimate string the submit page showed.
 *
 * Production's two formats are "<n> mins" and "<n.n> hr" (see
 * enrichment-analysis.ts's formatEstimate, which reproduces them). Anything
 * else — an em dash, an empty string, a value from some future format —
 * returns null and the row shows an em dash.
 *
 * Production reaches the same three cases through a `switch (true)` whose
 * fallthrough leaves the value `undefined`; `parseInt(undefined, 10)` is NaN,
 * and adding NaN minutes to a Date yields the string "Invalid Date" in the
 * table. Its own "no estimate" case hits that path: the submit page strips
 * hyphens out of the estimate before putting it in the URL, so its placeholder
 * "-" arrives as "" and never matches the `"-" == calcm` branch meant to catch
 * it.
 */
export function parseEstimateMinutes(calcm: string): number | null {
  const text = calcm.trim()
  const mins = /^(\d+(?:\.\d+)?)\s*mins?$/.exec(text)
  if (mins) return Number(mins[1])
  const hours = /^(\d+(?:\.\d+)?)\s*hr$/.exec(text)
  if (hours) return Number(hours[1]) * 60
  return null
}

/** Submission time plus the estimate, or null when there is no estimate to add. */
export function estimatedFinish(submittedAt: Date, calcm: string): Date | null {
  const minutes = parseEstimateMinutes(calcm)
  if (minutes === null) return null
  return new Date(submittedAt.getTime() + minutes * 60_000)
}

// ===== DOM wiring =====

interface Instance extends JobTrackerOptions {
  root: HTMLElement
  statusCell: HTMLElement | null
  logBox: HTMLElement | null
  resultLinks: HTMLAnchorElement[]
  pollHandle: number | null
  clockHandle: number | null
  logHandle: number | null
  logStopped: boolean
}

function field(root: HTMLElement, id: string): HTMLElement | null {
  return root.querySelector<HTMLElement>(`#${id}`)
}

function setField(root: HTMLElement, id: string, text: string): void {
  const el = field(root, id)
  if (el) el.textContent = text
}

/**
 * Show each result URL as text straight away, before the job is anywhere near
 * done. Production does the same, and the reason is on the page: the result
 * stays reachable for a week, and if the supercomputer goes quiet mid-job the
 * URL is the only way back to it. The anchors stay unclickable — no href —
 * until the job actually finishes.
 */
function showResultUrls(inst: Instance, result: JobResult, clickable: boolean): void {
  for (const a of inst.resultLinks) {
    const key = a.dataset.resultKey
    const url = key ? result.urls[key] : undefined
    if (!url) continue
    a.textContent = url
    if (clickable) {
      a.href = url
      a.target = '_blank'
      a.rel = 'noopener noreferrer'
    }
  }
}

async function loadResultUrls(inst: Instance, clickable: boolean): Promise<void> {
  try {
    showResultUrls(inst, await getJobResult(inst.jobId, inst.backend, inst.jobType), clickable)
  } catch (err) {
    // A backend that is down cannot tell us the URLs. Leave the cells empty
    // rather than writing a guessed URL the user might note down.
    console.warn('Failed to fetch result URLs:', err)
  }
}

function setStatus(inst: Instance, status: string): void {
  if (!inst.statusCell) return
  inst.statusCell.textContent = status
  // Production paints a finished job's status red, which everywhere else on
  // this site means something went wrong. Same job, same emphasis, colour that
  // agrees with the word.
  inst.statusCell.className = FINISHED_STATUSES.has(status)
    ? 'fw-bold text-success'
    : FAILED_STATUSES.has(status)
      ? 'fw-bold text-danger'
      : ''
}

function stopPolling(inst: Instance): void {
  if (inst.pollHandle != null) {
    window.clearTimeout(inst.pollHandle)
    inst.pollHandle = null
  }
}

function stopLogPolling(inst: Instance): void {
  inst.logStopped = true
  if (inst.logHandle != null) {
    window.clearTimeout(inst.logHandle)
    inst.logHandle = null
  }
}

async function poll(inst: Instance): Promise<void> {
  try {
    const status = await getJobStatus(inst.jobId, inst.backend)
    setStatus(inst, status.status)

    if (FINISHED_STATUSES.has(status.status)) {
      stopPolling(inst)
      await loadResultUrls(inst, true)
      // One more log read, then stop: the job is over and the log will not
      // grow again.
      await refreshLog(inst)
      stopLogPolling(inst)
      return
    }
    if (FAILED_STATUSES.has(status.status)) {
      stopPolling(inst)
      await refreshLog(inst)
      stopLogPolling(inst)
      return
    }
  } catch (err) {
    console.warn('Status poll failed:', err)
  }
  inst.pollHandle = window.setTimeout(() => void poll(inst), POLL_INTERVAL_MS)
}

function renderLog(box: HTMLElement, text: string): void {
  const heading = document.createElement('h3')
  heading.className = 'h5 mt-4'
  heading.textContent = 'Execution Log'

  const pre = document.createElement('pre')
  pre.className = 'small bg-light border rounded p-2 mb-0'
  pre.style.maxHeight = '400px'
  pre.style.overflow = 'auto'

  const code = document.createElement('code')
  // textContent, not innerHTML: production interpolates the log body straight
  // into the page, and a log is upstream text this app does not author.
  code.textContent = text
  pre.appendChild(code)

  box.replaceChildren(heading, pre)
}

function renderLogPlaceholder(box: HTMLElement, message: string): void {
  if (box.querySelector('pre')) return // never replace a log we already have
  const heading = document.createElement('h3')
  heading.className = 'h5 mt-4'
  heading.textContent = 'Execution Log'
  const p = document.createElement('p')
  p.className = 'text-muted small mb-0'
  p.textContent = message
  box.replaceChildren(heading, p)
}

async function refreshLog(inst: Instance): Promise<void> {
  const box = inst.logBox
  if (!box) return
  try {
    const text = await getJobLog(inst.jobId, inst.backend)
    if (text.trim()) renderLog(box, text)
    else renderLogPlaceholder(box, 'Log file not available yet. Please wait…')
  } catch {
    renderLogPlaceholder(box, 'Log file not available yet. This page refreshes on its own.')
  }
}

function pollLog(inst: Instance): void {
  void refreshLog(inst).finally(() => {
    // The terminal-status branch of poll() reads the log one last time and
    // then sets this, so a read already in flight does not reschedule itself
    // after the job is over.
    if (!inst.logStopped) {
      inst.logHandle = window.setTimeout(() => pollLog(inst), POLL_INTERVAL_MS)
    }
  })
}

export const JobTracker = {
  init(root: HTMLElement, options: JobTrackerOptions): void {
    const inst: Instance = {
      ...options,
      root,
      statusCell: field(root, 'status'),
      logBox: field(root, 'execution-log'),
      resultLinks: Array.from(root.querySelectorAll<HTMLAnchorElement>('a[data-result-key]')),
      pollHandle: null,
      clockHandle: null,
      logHandle: null,
      logStopped: false,
    }

    setField(root, 'project-title', options.title || EM_DASH)
    setField(root, 'request-id', options.jobId)

    const submittedAt = parseWabiSubmitTime(options.jobId) ?? new Date()
    setField(root, 'submitted-at', formatStamp(submittedAt))

    const finish = estimatedFinish(submittedAt, options.calcm)
    setField(root, 'estimated-finishing-time', finish ? formatStamp(finish) : EM_DASH)

    const tick = (): void => setField(root, 'current-time', formatStamp(new Date()))
    tick()
    inst.clockHandle = window.setInterval(tick, CLOCK_INTERVAL_MS)

    // Text now, href when it finishes — see showResultUrls.
    void loadResultUrls(inst, false)

    pollLog(inst)
    void poll(inst)
  },
}
