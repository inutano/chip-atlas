// frontend/pages/enrichment-analysis.ts
// GenomeTabs + FacetFilter + dataset A/B inputs (BED/genes/count, file upload) + job submit.

import { GenomeTabs } from '../components/genome-tabs'
import { FacetFilter } from '../components/facet-filter'
import { submitJob } from '../api/client'

interface PageData {
  genomes: Record<string, string>
  prefill: {
    taxonomy?: string
    genes?: string
    genesetA?: string
    genesetB?: string
  }
}

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

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const facet = $('facet-filter')
  const status = $('submit-status')

  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    if (FacetFilter.getCondition(facet)) {
      await FacetFilter.setGenome(facet, detail.genome)
    } else {
      await FacetFilter.init(facet, detail.genome)
    }
  })

  GenomeTabs.init(tabs, data.genomes)

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
