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

// ===== Job submission payload =====
// D7 (Task C1, corrected by the coordinator after the enrichment-shaped
// rename table didn't cover this page): production's Diff Analysis sends
// its own WABI field names, but a *different* mapping than Enrichment
// Analysis's — antigenClass here is the diffbind/dmr experiment-type radio,
// not an antigen, and bedAFile/bedBFile are newline-joined ID strings, not
// arrays. Verified against the pre-purge production JS
// (public/js/pj/diff_analysis.js's retrievePostData()):
//
//   antigenClass  "diffbind" | "dmr"   (the experiment-type radio)
//   typeA/typeB   "srx"                (constant — NOT sent here, see below)
//   bedAFile      newline-joined dataset A ids
//   descriptionA  dataset A title
//   bedBFile      newline-joined dataset B ids
//   descriptionB  dataset B title
//   title         analysis title
//   genome        genome assembly
//   cellClass     "empty"              (constant — NOT sent here)
//   permTime      1                    (constant — NOT sent here)
//   threshold     50 (diffbind) | 999 (dmr) — an operational constant keyed
//                 on antigenClass, NOT the user-facing "Threshold for
//                 Significance" fixed in enrichment-analysis.ts (D10) and
//                 NOT wired to it: diff analysis has no threshold control
//                 in the UI on either site.
//
// typeA/typeB/cellClass/permTime/threshold/sbatchOptions/address/format/
// result are deliberately left out of this payload — they're constants or
// operational values with no UI control, owned by the task after this one
// (WabiService merging them in), same as C2 for enrichment-analysis.ts.
export interface DiffFormState {
  genome: string
  analysisType: 'dmr' | 'diffbind'
  idsA: string[]
  idsB: string[]
  title: string
  dataATitle: string
  dataBTitle: string
}

export function buildDiffAnalysisParams(form: DiffFormState): Record<string, unknown> {
  return {
    genome: form.genome,
    antigenClass: form.analysisType,
    bedAFile: form.idsA.join('\n'),
    descriptionA: form.dataATitle,
    bedBFile: form.idsB.join('\n'),
    descriptionB: form.dataBTitle,
    title: form.title,
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

    const params = buildDiffAnalysisParams({
      genome: currentGenome,
      analysisType: getAnalysisType(),
      idsA,
      idsB,
      title: ($('title') as HTMLInputElement).value,
      dataATitle: ($('dataA-title') as HTMLInputElement).value,
      dataBTitle: ($('dataB-title') as HTMLInputElement).value,
    })

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

// Guarded so buildDiffAnalysisParams can be imported and unit-tested under
// plain Node, which has no `document` — see diff-analysis.test.ts, and
// enrichment-analysis.ts / colo-result.ts for the same pattern.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
