// frontend/pages/diff-analysis.ts
// GenomeTabs + analysis-type radio + two ID textareas + estimated time + job submit.

import { GenomeTabs } from '../components/genome-tabs'
import { initInfoPopovers } from '../components/info-popover'
import { submitJob, getEstimatedTime } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

interface DiffAnalysisExamples {
  [species: string]: {
    diffbind: { dataSetA: string[]; dataSetB: string[] }
    dmr: { dataSetA: string[]; dataSetB: string[] }
  }
}

// Copy lifted verbatim from production's js/pj/diff_analysis.js helpText
// object (around lines 286-288), wired to the three title-field ⓘ buttons
// the same way Task 16 wired HELP_TEXT on the other analysis pages.
const HELP_TEXT: Record<string, string> = {
  'project-title':
    'Enter a title for this submission.\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  'dataset-a-title':
    'Enter a title for the data selected in "2. Enter dataset A".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  'dataset-b-title':
    'Enter a title for the data selected in "3. Enter dataset B".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
}

let currentGenome = ''
let examplesPromise: Promise<DiffAnalysisExamples> | null = null

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

// production's genomeSelected() strips the trailing assembly digits to key
// into diff-analysis.examples.json ("hg38" -> "hg", "mm10" -> "mm", ...).
function genomeSpecies(genome: string): string {
  return genome.replace(/\d+$/, '')
}

function loadExamples(): Promise<DiffAnalysisExamples> {
  if (!examplesPromise) {
    examplesPromise = fetch('/diff-analysis.examples.json').then((res) => {
      if (!res.ok) throw new Error(`examples fetch: ${res.status}`)
      return res.json() as Promise<DiffAnalysisExamples>
    })
  }
  return examplesPromise
}

async function refreshEstimate(): Promise<void> {
  const ids = [
    ...parseIds(($('dataA-text') as HTMLTextAreaElement).value),
    ...parseIds(($('dataB-text') as HTMLTextAreaElement).value),
  ]
  const out = $('estimated-run-time')
  if (ids.length === 0) {
    out.textContent = '—'
    return
  }
  try {
    const res = await getEstimatedTime(ids, getAnalysisType())
    out.textContent = res.minutes != null ? `${res.minutes} min` : '—'
  } catch (err) {
    console.error(err)
    out.textContent = '(failed)'
  }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const status = $('submit-status')

  // Seed default titles the way production's putDefaultTitles() does on
  // window.onload. Production's title inputs are empty in markup; only the
  // JS-applied values carry the (lower-case) "dataset A"/"dataset B" seeds.
  ;($('title') as HTMLInputElement).value = 'My project'
  ;($('dataA-title') as HTMLInputElement).value = 'dataset A'
  ;($('dataB-title') as HTMLInputElement).value = 'dataset B'

  tabs.addEventListener('genome-change', (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
  })

  GenomeTabs.init(tabs, data.genomes)
  initInfoPopovers(document, HELP_TEXT)

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

  function wireExampleLink(linkId: string, textareaId: string, key: 'dataSetA' | 'dataSetB'): void {
    $(linkId).addEventListener('click', (e) => {
      e.preventDefault()
      if (!currentGenome) { status.textContent = 'Select a genome tab first.'; return }
      void (async () => {
        try {
          const examples = await loadExamples()
          const species = examples[genomeSpecies(currentGenome)]
          const ids = species?.[getAnalysisType()]?.[key] ?? []
          if (ids.length === 0) {
            status.textContent = 'No example data available for this genome and experiment type.'
            return
          }
          ;($(textareaId) as HTMLTextAreaElement).value = ids.join('\n')
          status.textContent = ''
          void refreshEstimate()
        } catch (err) {
          console.error(err)
          status.textContent = 'Failed to load example data.'
        }
      })()
    })
  }

  wireExampleLink('try-example-a', 'dataA-text', 'dataSetA')
  wireExampleLink('try-example-b', 'dataB-text', 'dataSetB')

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

    // D7 (Task C1): dataA_title/dataB_title -> descriptionA/descriptionB are
    // WABI's own field names, per the rename table shared with
    // enrichment-analysis.ts's buildEnrichmentParams. genome/analysis/
    // dataA_ids/dataB_ids are out of that table's scope and unchanged here.
    const params = {
      genome: currentGenome,
      analysis: getAnalysisType(),
      dataA_ids: idsA,
      dataB_ids: idsB,
      title: ($('title') as HTMLInputElement).value,
      descriptionA: ($('dataA-title') as HTMLInputElement).value,
      descriptionB: ($('dataB-title') as HTMLInputElement).value,
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
