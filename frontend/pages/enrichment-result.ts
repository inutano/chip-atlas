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
