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
