// frontend/pages/diff-analysis.ts
// GenomeTabs + analysis-type radio + two ID textareas + estimated time + job submit.

import { GenomeTabs } from '../components/genome-tabs'
import { submitJob, getEstimatedTime } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

let currentGenome = ''

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function getAnalysisType(): 'dmr' | 'diffbind' {
  const r = document.querySelector<HTMLInputElement>('input[name="analysis-type"]:checked')
  return r?.value === 'dmr' ? 'dmr' : 'diffbind'
}

function parseIds(text: string): string[] {
  return text.split(/[\s,]+/).map((s) => s.trim()).filter((s) => s.length > 0)
}

async function refreshEstimate(): Promise<void> {
  const ids = [
    ...parseIds(($('dataA-text') as HTMLTextAreaElement).value),
    ...parseIds(($('dataB-text') as HTMLTextAreaElement).value),
  ]
  const out = $('estimated-time')
  if (ids.length === 0) {
    out.textContent = 'Estimated run time: —'
    return
  }
  try {
    const res = await getEstimatedTime(ids, getAnalysisType())
    out.textContent = res.minutes != null ? `Estimated run time: ${res.minutes} min` : 'Estimated run time: —'
  } catch (err) {
    out.textContent = 'Estimated run time: (failed)'
  }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const status = $('submit-status')

  tabs.addEventListener('genome-change', (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
  })

  GenomeTabs.init(tabs, data.genomes)

  ;[$('dataA-text'), $('dataB-text')].forEach((el) => {
    let timer: number | null = null
    el.addEventListener('input', () => {
      if (timer != null) window.clearTimeout(timer)
      timer = window.setTimeout(refreshEstimate, 500)
    })
  })
  document.querySelectorAll<HTMLInputElement>('input[name="analysis-type"]').forEach((r) => {
    r.addEventListener('change', refreshEstimate)
  })

  $('submit-job').addEventListener('click', async () => {
    const idsA = parseIds(($('dataA-text') as HTMLTextAreaElement).value)
    const idsB = parseIds(($('dataB-text') as HTMLTextAreaElement).value)
    if (idsA.length === 0 || idsB.length === 0) {
      status.textContent = 'Both datasets must contain at least one experiment ID.'
      return
    }
    if (!currentGenome) {
      status.textContent = 'Select a genome tab first.'
      return
    }

    const params = {
      genome: currentGenome,
      analysis: getAnalysisType(),
      dataA_ids: idsA,
      dataB_ids: idsB,
      title: ($('title') as HTMLInputElement).value,
      dataA_title: ($('dataA-title') as HTMLInputElement).value,
      dataB_title: ($('dataB-title') as HTMLInputElement).value,
    }

    status.textContent = 'Submitting…'
    try {
      const result = await submitJob({ type: 'diff_analysis', params })
      window.location.href = `/diff_analysis_result?id=${encodeURIComponent(result.job_id)}&backend=${encodeURIComponent(result.backend)}`
    } catch (err) {
      console.error(err)
      status.textContent = 'Submit failed. Try again or check the service status.'
    }
  })
}

document.addEventListener('DOMContentLoaded', init)
