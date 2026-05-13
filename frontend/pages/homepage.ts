// frontend/pages/homepage.ts
// Fetches experiment count from /api/stats and updates the homepage display.

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
    // If the API call fails, keep the server-rendered count.
    console.warn('Failed to fetch stats:', err)
  }
}

document.addEventListener('DOMContentLoaded', init)
