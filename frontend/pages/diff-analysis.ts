// frontend/pages/diff-analysis.ts
// GenomeTabs + analysis-type radio + two ID textareas + estimated time + job submit.

import { GenomeTabs } from '../components/genome-tabs'
import { initInfoPopovers } from '../components/info-popover'
import { submitJob, getEstimatedTime, checkJobAvailability, type JobAvailability } from '../api/client'

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

// ===== Per-genome dataset state =====
// Production keeps a separate DOM subtree per genome tab (genome-prefixed
// ids: hg38DataSetA, mm10DataSetA, ...), so an id typed while hg38 is active
// structurally cannot leak into a submission made under mm10 — it lives in
// an element that isn't even part of the mm10 tab. This page renders one
// shared pair of textareas for all genomes (the pattern every page in this
// app uses via GenomeTabs — see enrichment-analysis.ts's FacetFilter.setGenome
// for the same single-DOM-plus-swap approach), so the equivalent guarantee is
// implemented as a small in-memory store keyed by genome code: on every
// 'genome-change' the outgoing genome's textarea values are saved here and
// the incoming genome's saved values (blank if never visited) are loaded in.
// The dataset never survives a tab switch under someone else's genome code,
// which is the actual bug this task fixes — the DOM topology production uses
// to get there is not reproduced, only the observable guarantee.
//
// Title fields are deliberately NOT part of this store — see the "Do NOT
// reset the title fields on tab click" note below, where init() seeds them
// once and this file otherwise leaves them alone.
export interface GenomeDatasetState {
  idsA: string
  idsB: string
}

const BLANK_DATASET_STATE: GenomeDatasetState = { idsA: '', idsB: '' }

export function createGenomeDatasetStore(): {
  get(genome: string): GenomeDatasetState
  set(genome: string, state: GenomeDatasetState): void
  clear(genome: string): void
} {
  const store = new Map<string, GenomeDatasetState>()
  return {
    get(genome: string): GenomeDatasetState {
      // Return a copy, not the shared BLANK_DATASET_STATE reference: no
      // caller mutates the returned object today, but handing out the same
      // constant to every unvisited genome would make an in-place edit by
      // one genome's caller silently visible to every other unvisited
      // genome too, defeating the per-genome isolation this store exists
      // to guarantee.
      const existing = store.get(genome)
      return existing ? existing : { ...BLANK_DATASET_STATE }
    },
    set(genome: string, state: GenomeDatasetState): void {
      store.set(genome, state)
    },
    clear(genome: string): void {
      store.set(genome, { ...BLANK_DATASET_STATE })
    },
  }
}

const datasetStore = createGenomeDatasetStore()

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
    // "mins", not "min": production writes `minutes + " mins"` here, and the
    // result page parses this same string back out of the URL to work out the
    // estimated finishing time (see job-tracker.ts's parseEstimateMinutes).
    out.textContent = res.minutes != null ? `${res.minutes} mins` : '—'
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

// ===== Availability =====
// GET /jobs/available?type=diff_analysis (routes/jobs.rb -> ComputeRouter,
// see lib/services/compute_router.rb) is the honest source of truth for
// whether a compute backend currently serves this job type. Diff analysis
// maps to WABI only (no WES fallback, unlike enrichment analysis), so this
// notice shows exactly when WABI itself is unreachable. From launch until
// 2026-09-24, WABI was believed not to serve diff-analysis jobs at all, so
// diff_analysis was mapped to no backend and this endpoint always came back
// { backend: null, available: false } regardless of WABI's reachability --
// the project owner confirmed on 2026-09-24 that WABI serves them again and
// had ComputeRouter's routing map updated (see
// docs/review-2026-09-23/findings/ui-diff-analysis.md, DA-01). Originally,
// nothing on this page even called this endpoint, so the user saw a
// complete, fillable form that could never actually submit.
export const UNAVAILABLE_MESSAGE =
  'Diff analysis is currently unavailable: no compute backend is serving this job type right now. Please check back later.'

export interface AvailabilityUiState {
  submitDisabled: boolean
  noticeHidden: boolean
  noticeText: string
}

// Pure so it can be unit-tested without a DOM (diff-analysis.test.ts) and so
// the fail-safe decision below is made in exactly one place.
//
// `availability === null` means the availability check itself failed (a
// network error, a non-2xx response, or a malformed body) -- not that the
// backend reported itself unavailable. This deliberately fails OPEN: treat
// a failed check the same as "available" and leave the form usable.
// Reasoning:
//   - The task brief requires the page to "still work when the backend *is*
//     available" by default, i.e. the unavailable state must never be the
//     thing a working page has to undo. A flaky /jobs/available request is
//     not evidence the backend can't work; treating it as proof of
//     unavailability would turn a transient network blip into a hard block.
//   - Failing open cannot make a submission silently wrong: POST
//     /jobs/submit independently re-checks ComputeRouter and returns 503
//     when the backend genuinely isn't available (routes/jobs.rb), and this
//     page's existing submit handler already turns that into a visible
//     "Submit failed" message. So the worst case of failing open is a
//     failed submit attempt the user can see and retry -- not a job that
//     silently goes to the wrong place or a lost analysis.
//   - Failing closed (treating a failed check as "unavailable") would be
//     the safer-looking default on its face, but here it trades a visible,
//     recoverable failure (a rejected submit) for an invisible, unrecoverable
//     one (a working feature permanently hidden behind a banner because one
//     fetch hiccuped), which is worse for this page.
export function resolveAvailabilityUiState(availability: JobAvailability | null): AvailabilityUiState {
  if (availability === null || availability.available) {
    return { submitDisabled: false, noticeHidden: true, noticeText: '' }
  }
  return { submitDisabled: true, noticeHidden: false, noticeText: UNAVAILABLE_MESSAGE }
}

async function applyAvailability(): Promise<void> {
  let availability: JobAvailability | null = null
  try {
    availability = await checkJobAvailability('diff_analysis')
  } catch (err) {
    console.error(err)
    availability = null
  }
  const ui = resolveAvailabilityUiState(availability)
  const notice = $('unavailable-notice')
  notice.textContent = ui.noticeText
  notice.hidden = ui.noticeHidden
  ;($('submit-job') as HTMLButtonElement).disabled = ui.submitDisabled
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
    // Save the outgoing genome's dataset values (if any genome was already
    // selected — the first 'genome-change', fired synchronously by
    // GenomeTabs.init below, has no outgoing genome to save) before
    // swapping in the incoming genome's saved (or blank) values.
    if (currentGenome) {
      datasetStore.set(currentGenome, {
        idsA: ($('dataA-text') as HTMLTextAreaElement).value,
        idsB: ($('dataB-text') as HTMLTextAreaElement).value,
      })
    }
    currentGenome = detail.genome
    const state = datasetStore.get(currentGenome)
    ;($('dataA-text') as HTMLTextAreaElement).value = state.idsA
    ;($('dataB-text') as HTMLTextAreaElement).value = state.idsB
    void refreshEstimate()
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
  // Production binds eraseTextarea() to both experiment-type radios, so
  // toggling ChIP/ATAC/DNase-seq <-> Bisulfite-seq blanks both dataset
  // textareas (and resets the run-time estimate) for the active genome —
  // production's eraseTextarea() only ever touches genomeSelected()'s own
  // fields, never other tabs' saved data, which this mirrors by clearing
  // only currentGenome's entry in datasetStore. Without this, ChIP peak IDs
  // typed under "ChIP / ATAC / DNase-seq" would silently carry into a
  // Bisulfite-seq/DMR submission — the same silent-wrong-result risk as the
  // genome axis this task otherwise fixes.
  document.querySelectorAll<HTMLInputElement>('input[name="analysis-type"]').forEach((r) => {
    r.addEventListener('change', () => {
      ;($('dataA-text') as HTMLTextAreaElement).value = ''
      ;($('dataB-text') as HTMLTextAreaElement).value = ''
      if (currentGenome) datasetStore.clear(currentGenome)
      void refreshEstimate()
    })
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

  void applyAvailability()

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
      // See enrichment-analysis.ts's submit handler: production carries the
      // title and the run-time estimate to the result page in the URL.
      const calcm = document.getElementById('estimated-run-time')?.textContent ?? ''
      window.location.href = `/diff_analysis_result?id=${encodeURIComponent(result.job_id)}` +
        `&backend=${encodeURIComponent(result.backend)}` +
        `&title=${encodeURIComponent(($('title') as HTMLInputElement).value)}` +
        `&calcm=${encodeURIComponent(calcm)}`
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
