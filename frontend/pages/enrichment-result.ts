// frontend/pages/enrichment-result.ts
// Mounts JobTracker over the job-info table in views/enrichment_analysis_result.erb.

import { JobTracker } from '../components/job-tracker'
import { readResultPageParams } from '../components/result-page-params'

function init(): void {
  const container = document.getElementById('job-tracker')
  if (!container) return

  const params = readResultPageParams(window.location.search)
  if (!params) {
    const err = document.getElementById('error-state')
    if (err) {
      err.textContent = 'Missing id or backend parameter in URL.'
      err.hidden = false
    }
    container.hidden = true
    return
  }

  JobTracker.init(container, { ...params, jobType: 'enrichment_analysis' })
}

document.addEventListener('DOMContentLoaded', init)
