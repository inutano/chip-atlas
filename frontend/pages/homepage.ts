// frontend/pages/homepage.ts
// Fetches experiment count from /api/stats and updates the homepage display,
// and renders a service-outage banner from /status (SHELL-02).
//
// Production hand-edits a red notice straight into its deployed
// updates.markdown whenever a feature goes down (e.g. "Diff Analysis is
// temporarily unavailable..."). This repo's updates.markdown ships from
// source control instead, so there is no equivalent "edit the file on the
// server" workflow to reproduce - the owner chose an automatic banner driven
// by GET /status's per-feature health map (see frontend/api/client.ts's
// ServiceStatus) instead.

import { getStats, serviceStatus } from '../api/client'

const FEATURE_NAMES: Record<string, string> = {
  peak_browser: 'Peak Browser',
  enrichment_analysis: 'Enrichment Analysis',
  diff_analysis: 'Diff Analysis',
  target_genes: 'Target Genes',
  colo: 'Colocalization',
  search: 'Dataset Search',
}

// Fixed display order (SHELL-02's brief), not object property order - /status's
// JSON makes no promise about key order, and Object.keys order over a
// hand-typed literal is an implementation detail this shouldn't depend on.
const FEATURE_ORDER = ['peak_browser', 'enrichment_analysis', 'diff_analysis', 'target_genes', 'colo', 'search']

// Pure: one line per known feature whose value is neither 'ok' nor
// 'ok (backup)' (Enrichment Analysis's WABI-backup path counts as up, not
// down). A feature key `features` doesn't have is treated the same as "ok"
// (no line), and a key `features` has that isn't one of the six known
// features is ignored rather than rendered as "undefined is temporarily
// unavailable...".
export function unavailableFeatureLines(features: Record<string, string>): string[] {
  return FEATURE_ORDER
    .filter((key) => key in features && features[key] !== 'ok' && features[key] !== 'ok (backup)')
    .map((key) => `${FEATURE_NAMES[key]} is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.`)
}

async function initServiceNotice(): Promise<void> {
  const notice = document.getElementById('service-notice')
  if (!notice) return

  let lines: string[]
  try {
    const status = await serviceStatus()
    lines = unavailableFeatureLines(status.features)
  } catch (err) {
    // A failed /status call must render nothing - an outage in the status
    // endpoint itself must not read as every feature being down.
    console.warn('Failed to fetch service status:', err)
    return
  }
  if (lines.length === 0) return

  notice.replaceChildren(...lines.map((line) => {
    const p = document.createElement('p')
    p.className = 'text-danger fw-bold mb-1'
    p.textContent = line
    return p
  }))
  notice.hidden = false
}

async function init(): Promise<void> {
  const countEl = document.getElementById('experiment-count')
  if (countEl) {
    try {
      const stats = await getStats()
      if (stats.total_experiments_formatted) {
        countEl.textContent = stats.total_experiments_formatted
      }
    } catch (err) {
      // If the API call fails, keep the server-rendered count.
      console.warn('Failed to fetch stats:', err)
    }
  }

  await initServiceNotice()
}

// Guarded so unavailableFeatureLines can be imported and unit-tested under
// plain Node, which has no `document` — see homepage.test.ts, and
// enrichment-analysis.ts / colo.ts / peak-browser.ts for the same pattern.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
