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

// ===== "type to search" wiring for the two optional subclass list boxes =====
// (mirrors frontend/pages/peak-browser.ts — see its header comment for why)

interface SubclassSearch {
  input: HTMLInputElement
  mount: HTMLElement
  idByLabel: Map<string, string>
}

function subclassSelect(mount: HTMLElement): HTMLSelectElement | null {
  return mount.querySelector('select')
}

function refreshSubclassSearch(s: SubclassSearch): void {
  const select = subclassSelect(s.mount)
  if (!select) return
  const items: string[] = []
  s.idByLabel.clear()
  for (const opt of Array.from(select.options)) {
    const text = opt.textContent ?? opt.value
    items.push(text)
    s.idByLabel.set(text, opt.value)
  }
  Autocomplete.setItems(s.input, items)
}

function wireSubclassSearch(input: HTMLInputElement, mount: HTMLElement): SubclassSearch {
  const s: SubclassSearch = { input, mount, idByLabel: new Map() }

  Autocomplete.init(input, [], (label) => {
    const select = subclassSelect(mount)
    const id = s.idByLabel.get(label)
    if (!select || id === undefined) return
    select.value = id
    select.dispatchEvent(new Event('change', { bubbles: true }))
  })

  input.addEventListener('input', () => {
    const select = subclassSelect(mount)
    if (!select) return
    const q = input.value.trim().toLowerCase()
    for (const opt of Array.from(select.options)) {
      opt.hidden = q !== '' && !(opt.textContent ?? '').toLowerCase().includes(q)
    }
  })

  return s
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
    const res = await fetch('/jobs/estimated_time', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ids: [], analysis: 'enrichment' }),
    })
    if (!res.ok) throw new Error(`estimated_time: ${res.status}`)
    const data = (await res.json()) as { minutes: number | null }
    out.textContent = data.minutes != null ? `${data.minutes} min` : '—'
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

  const mount: Record<'track_class' | 'track_subclass' | 'cell_type_class' | 'cell_type_subclass' | 'qval', HTMLElement> = {
    track_class:        $('facet-track-class'),
    track_subclass:     $('facet-track-subclass'),
    cell_type_class:    $('facet-cell-type-class'),
    cell_type_subclass: $('facet-cell-type-subclass'),
    qval:               $('facet-qval'),
  }

  const trackSearch = wireSubclassSearch($('track-subclass-input') as HTMLInputElement, mount.track_subclass)
  const cellSearch = wireSubclassSearch($('cell-type-subclass-input') as HTMLInputElement, mount.cell_type_subclass)

  facet.addEventListener('facet-change', () => {
    refreshSubclassSearch(trackSearch)
    refreshSubclassSearch(cellSearch)
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
