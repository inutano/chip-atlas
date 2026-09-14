// frontend/pages/enrichment-analysis.ts
// GenomeTabs + FacetFilter (list-box mode, six-panel grid) + dataset A/B inputs
// (BED/genes/count, file upload, "Try with example") + estimated run time + job submit.
//
// The "Track type (optional)" and "Cell type (optional)" panels use the same
// "type to search" + ListBox pairing as frontend/pages/peak-browser.ts, for
// the same reason documented there: Autocomplete drives the *same* <select>
// FacetFilter owns (via a native `change` event) instead of building a second,
// competing ListBox, so the cascade and FacetFilter.getCondition() stay correct.

import { GenomeTabs } from '../components/genome-tabs'
import { FacetFilter } from '../components/facet-filter'
import { Autocomplete } from '../components/autocomplete'
import { initInfoPopovers } from '../components/info-popover'
import { submitJob, getEstimatedTime } from '../api/client'

interface PageData {
  genomes: Record<string, string>
  prefill: {
    taxonomy?: string
    genes?: string
    genesetA?: string
    genesetB?: string
  }
}

// Copy lifted verbatim from production's js/pj/enrichment_analysis.js
// helpText object (the note1/note2 fragments are appended exactly as
// production's own $(".infoBtn").click handler concatenates them).
const NOTE1 =
  'Acceptable identifiers:\n  Official gene symbols (e.g. POU5F1)\n  Ensembl IDs (e.g. ENSG00000204531)\n  Uniprot IDs (e.g. Q01860)\n  RefSeq gene IDs (e.g. NM_002701)\n\nOfficial gene symbols must be entered according to following nomenclatures:\n  H. sapiens: HGNC\n  M. musculus: MGI\n  R. norvegicus: RGD\n  D. melanogaster: FlyBase\n  C. elegans: WormBase\n  S. cerevisiae: SGD\n\nAcceptable example:\n  POU5F1\n  TP53\n\nBad example:\n  OCT4\n  p53'
const NOTE2 =
  'Example:\n  chr1<tab>531435<tab>543845\n  chr2<tab>738543<tab>742321\n\nAcceptable genome assemblies:\n    hg19, hg38 (H. sapiens)\n    mm9, mm10 (M. musculus)\n    rn6 (R. norvegicus)\n    dm3, dm6 (D. melanogaster)\n    ce10, ce11 (C. elegans)\n    sacCer3 (S. cerevisiae)\n\n'

const HELP_TEXT: Record<string, string> = {
  threshold:
    'Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If set to 50, peaks with Q values < 1E-05 are used to evaluate overlap with data sets A and, when available, B. Ignore if experiment type is set to Bisulfite-seq.',
  'genomic-regions':
    'Check this to search for common epigenetic features within given genomic regions (UCSC BED format).\n\n' + NOTE2,
  'gene-list':
    'Check this to search for common epigenetic features around given genes.\n\n' + NOTE1,
  'gene-count-table':
    'Check this to upload a two-group gene count table (raw integer counts in CSV or TSV) with a header to search for common epigenetic features around highly expressed genes in each group.\n\nThe first column of the header is ignored. The other columns in the header specify the sample names for the corresponding columns (e.g., "wt_1" indicates replicate 1 of the "wt" group; the replicate number should be appended to the sample name, following an underscore). \n\nThe first column of the count table should contain gene names or IDs.\n\n' +
    NOTE1,
  permutation:
    'Check this to compare ‘dataset A’ with a random background. In this case, each genomic location of ‘dataset A’ is permuted on a random chromosome at a random position for the specified times. Increasing the permutation times will provide a highly randomized background, or a high quality statistical test, but the calculation time will be longer.',
  'dataset-b-bed':
    "Check this to compare 'dataset A' with another dataset (UCSC BED format).\n\n" + NOTE2,
  'analysis-title':
    'Enter a title for this submission.\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
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

function readFileToTextarea(input: HTMLInputElement, textarea: HTMLTextAreaElement): void {
  input.addEventListener('change', () => {
    const file = input.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => {
      textarea.value = String(reader.result || '')
    }
    reader.readAsText(file)
  })
}

function getCheckedValue(name: string): string {
  const r = document.querySelector<HTMLInputElement>(`input[name="${name}"]:checked`)
  return r?.value || ''
}

function syncDatasetBVisibility(): void {
  const aType = getCheckedValue('dataA-type')
  const bType = getCheckedValue('dataB-type')

  // Refseq + userlist are gene-list-mode only
  const isGeneMode = aType === 'gene'
  ;(document.getElementById('dataB-refseq') as HTMLInputElement).disabled = !isGeneMode
  ;(document.getElementById('dataB-userlist') as HTMLInputElement).disabled = !isGeneMode

  // Random permutation row visible only when dataset B = rnd
  ;($('permutation-row') as HTMLElement).hidden = bType !== 'rnd'

  // Textarea + file picker visible when dataset B needs content (bed or userlist)
  const needsInput = bType === 'bed' || bType === 'userlist'
  ;(document.getElementById('dataB-text') as HTMLElement).hidden = !needsInput
  ;(document.getElementById('dataB-file') as HTMLElement).hidden = !needsInput

  // Helper note
  const note = $('dataB-note')
  if (bType === 'rnd') note.textContent = 'Random permutation needs no input.'
  else if (bType === 'refseq') note.textContent = 'All Refseq coding genes (excluding dataset A) are used.'
  else if (needsInput) note.textContent = ''
  else note.textContent = ''
}

// ===== Estimated run time =====
// Reuses the shared POST /jobs/estimated_time endpoint (see routes/jobs.rb and
// frontend/pages/diff-analysis.ts). That endpoint only models runtime for the
// diff-analysis 'dmr'/'diffbind' formulas — enrichment-analysis jobs have no
// modeled formula server-side yet, so this always resolves to the same
// em-dash placeholder the panel starts with. Wiring it here (rather than
// leaving the placeholder static) keeps the affordance ready for the day a
// server-side estimate is added, without touching job-submission logic.
async function refreshEstimate(): Promise<void> {
  const out = document.getElementById('estimated-run-time')
  if (!out) return
  try {
    const res = await getEstimatedTime([], 'enrichment')
    out.textContent = res.minutes != null ? `${res.minutes} min` : '—'
  } catch (err) {
    console.error(err)
    out.textContent = '—'
  }
}

// ===== Try with example =====
async function loadExample(): Promise<void> {
  if (!currentGenome) return
  const status = $('submit-status')
  try {
    const res = await fetch(`/examples/${encodeURIComponent(currentGenome)}/bedA.txt`)
    if (!res.ok) throw new Error(`example fetch: ${res.status}`)
    const text = await res.text()
    ;(document.getElementById('dataA-bed') as HTMLInputElement).checked = true
    ;($('dataA-text') as HTMLTextAreaElement).value = text
    syncDatasetBVisibility()
  } catch (err) {
    console.error(err)
    status.textContent = 'Failed to load example data.'
  }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const status = $('submit-status')

  // Anchor element for FacetFilter's internal registry / facet-change event.
  // In list-box mode the five facets render into their own mount points
  // (below), so this container never enters the document.
  const facet = document.createElement('div')

  // Production's Enrichment Analysis exposes only experiment type, cell type
  // class and threshold - the subclass panels belong to the Peak Browser.
  const mount: Record<'track_class' | 'cell_type_class' | 'qval', HTMLElement> = {
    track_class:        $('facet-track-class'),
    cell_type_class:    $('facet-cell-type-class'),
    qval:               $('facet-qval'),
  }


  facet.addEventListener('facet-change', () => {
    void refreshEstimate()
  })

  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
    if (FacetFilter.getCondition(facet)) {
      await FacetFilter.setGenome(facet, detail.genome)
    } else {
      await FacetFilter.init(facet, detail.genome, { render: 'listbox', mount })
    }
  })

  GenomeTabs.init(tabs, data.genomes)
  initInfoPopovers(document, HELP_TEXT)

  // Pre-fill from POST body if present
  if (data.prefill.genesetA) ($('dataA-text') as HTMLTextAreaElement).value = data.prefill.genesetA
  if (data.prefill.genesetB) ($('dataB-text') as HTMLTextAreaElement).value = data.prefill.genesetB
  else if (data.prefill.genes) ($('dataA-text') as HTMLTextAreaElement).value = data.prefill.genes

  document.querySelectorAll<HTMLInputElement>('input[name="dataA-type"], input[name="dataB-type"]').forEach((r) => {
    r.addEventListener('change', syncDatasetBVisibility)
  })
  syncDatasetBVisibility()

  readFileToTextarea(
    $('dataA-file') as HTMLInputElement,
    $('dataA-text') as HTMLTextAreaElement,
  )
  readFileToTextarea(
    $('dataB-file') as HTMLInputElement,
    $('dataB-text') as HTMLTextAreaElement,
  )

  $('try-example').addEventListener('click', (e) => {
    e.preventDefault()
    void loadExample()
  })

  void refreshEstimate()

  $('submit-job').addEventListener('click', async () => {
    const condition = FacetFilter.getCondition(facet)
    if (!condition) { status.textContent = 'Filter not ready yet.'; return }

    const aType = getCheckedValue('dataA-type')
    const bType = getCheckedValue('dataB-type')
    const dataAText = ($('dataA-text') as HTMLTextAreaElement).value.trim()
    if (!dataAText) { status.textContent = 'Dataset A is empty.'; return }

    const params: Record<string, unknown> = {
      genome: condition.genome,
      track_class: condition.track_class,
      cell_type_class: condition.cell_type_class,
      qval: condition.qval,
      dataA_type: aType,
      dataA: dataAText,
      dataB_type: bType,
      title: ($('title') as HTMLInputElement).value,
      dataA_title: ($('dataA-title') as HTMLInputElement).value,
      dataB_title: ($('dataB-title') as HTMLInputElement).value,
    }
    if (bType === 'rnd') params.permutations = getCheckedValue('dataB-perm')
    if (bType === 'bed' || bType === 'userlist') params.dataB = ($('dataB-text') as HTMLTextAreaElement).value

    status.textContent = 'Submitting…'
    try {
      const result = await submitJob({ type: 'enrichment_analysis', params })
      window.location.href = `/enrichment_analysis_result?id=${encodeURIComponent(result.job_id)}&backend=${encodeURIComponent(result.backend)}`
    } catch (err) {
      console.error(err)
      status.textContent = 'Submit failed. Try again or check the service status.'
    }
  })
}

document.addEventListener('DOMContentLoaded', init)
