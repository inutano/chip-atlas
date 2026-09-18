// frontend/pages/colo.ts
// Colocalization setup: genome tabs + direction radio + primary/secondary autocomplete + submit/download.

import { GenomeTabs } from '../components/genome-tabs'
import { Autocomplete } from '../components/autocomplete'
import { getColoIndex, type ColoIndex } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

// === Availability ===
// The picker cannot currently produce a valid (genome, track, cell_type)
// combination: ChipAtlas::Analysis.colo_result_by_genome
// (lib/models/analysis.rb) has no reliable signal for which
// (antigen, cell-type-class) pairs actually have a precomputed colo result
// file on the archive -- see Q2 in
// docs/superpowers/plans/2026-09-18-post-parity-fixes.md ("Who produces the
// Colocalization index?"), still pending the collaborator as of
// 2026-09-19. Every entry the picker offers today routes through a
// `cell_list` of "-" (no known cell types), which the real archive 404s on
// for every combination -- this is a live navbar entry that fails on every
// query, not an edge case.
//
// Rather than present a full picker that always fails, show an honest
// "temporarily unavailable" notice and hide the picker -- the same
// treatment Diff Analysis got in this fix wave for its own defunct compute
// backend (see frontend/pages/diff-analysis.ts's Availability section).
// Unlike that page, there is no backend health check to poll here (the
// picker is unavailable by construction, not intermittently), so this is a
// static switch rather than a runtime check.
//
// /colo_result itself is NOT gated by this -- it renders correctly given
// real (genome, track, cell_type) query params (see colo-result.ts /
// ChipAtlas::ColoTsv); only the picker that can no longer produce valid
// params is disabled here.
//
// TO RE-ENABLE: once a real colo index lands (Q2) and
// Analysis.colo_result_by_genome reflects it, flip this to `false`. That is
// the only change needed here.
const COLO_PICKER_UNAVAILABLE = true

const UNAVAILABLE_MESSAGE =
  'Colocalization search is temporarily unavailable while the colocalization index is rebuilt upstream. Please check back later.'

let currentGenome = ''
let currentPrimary = ''
let currentSecondary = ''
const coloIndex: ColoIndex = {}

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

function getDirection(): 'track' | 'cell_type' {
  const r = document.querySelector<HTMLInputElement>('input[name="direction"]:checked')
  return r?.value === 'cell_type' ? 'cell_type' : 'track'
}

// Mirrors production's colo.js changePanelTitle(): the primary/secondary
// panel headings name whichever facet they currently hold, which flips with
// the search-mode radio.
function updatePanelTitles(): void {
  const primaryTitle = $('primary-panel-title')
  const secondaryTitle = $('secondary-panel-title')
  if (getDirection() === 'track') {
    primaryTitle.textContent = '2. Choose Antigen'
    secondaryTitle.textContent = '3. Choose Cell Type Class'
  } else {
    primaryTitle.textContent = '2. Choose Cell Type Class'
    secondaryTitle.textContent = '3. Choose Antigen'
  }
}

async function loadGenomeIndex(genome: string): Promise<void> {
  if (coloIndex[genome]) return
  try {
    const data = await getColoIndex(genome)
    coloIndex[genome] = data[genome]
  } catch (err) {
    console.warn('Failed to load colo index for', genome, err)
  }
}

function buildLinkParams(): URLSearchParams | null {
  if (!currentGenome || !currentPrimary || !currentSecondary) return null
  const direction = getDirection()
  const track = direction === 'track' ? currentPrimary : currentSecondary
  const cellType = direction === 'track' ? currentSecondary : currentPrimary
  return new URLSearchParams({ genome: currentGenome, track, cell_type: cellType })
}

async function init(): Promise<void> {
  if (COLO_PICKER_UNAVAILABLE) {
    const notice = $('colo-unavailable-notice')
    notice.textContent = UNAVAILABLE_MESSAGE
    notice.hidden = false
    $('colo-picker').hidden = true
    return
  }

  const data = readPageData()
  const pInput = $('primary-input') as HTMLInputElement
  const sInput = $('secondary-input') as HTMLInputElement

  function refresh(): void {
    const entry = coloIndex[currentGenome]
    if (!entry) {
      Autocomplete.setItems(pInput, [])
      Autocomplete.setItems(sInput, [])
      return
    }
    const direction = getDirection()
    if (direction === 'track') {
      Autocomplete.setItems(pInput, Object.keys(entry.track))
      const secondaries = currentPrimary && entry.track[currentPrimary]
        ? entry.track[currentPrimary]
        : Object.keys(entry.cell_type)
      Autocomplete.setItems(sInput, secondaries)
    } else {
      Autocomplete.setItems(pInput, Object.keys(entry.cell_type))
      const secondaries = currentPrimary && entry.cell_type[currentPrimary]
        ? entry.cell_type[currentPrimary]
        : Object.keys(entry.track)
      Autocomplete.setItems(sInput, secondaries)
    }
  }

  Autocomplete.init(pInput, [], (value) => {
    currentPrimary = value
    refresh()
  }, { pairedList: $('primary-list') })
  Autocomplete.init(sInput, [], (value) => {
    currentSecondary = value
  }, { pairedList: $('secondary-list') })

  document.querySelectorAll<HTMLInputElement>('input[name="direction"]').forEach((r) => {
    r.addEventListener('change', () => {
      currentPrimary = ''
      currentSecondary = ''
      pInput.value = ''
      sInput.value = ''
      updatePanelTitles()
      refresh()
    })
  })

  updatePanelTitles()

  const tabs = $('genome-tabs')
  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
    currentPrimary = ''
    currentSecondary = ''
    pInput.value = ''
    sInput.value = ''
    await loadGenomeIndex(currentGenome)
    refresh()
  })

  GenomeTabs.init(tabs, data.genomes)

  $('view-colo').addEventListener('click', () => {
    const params = buildLinkParams()
    if (!params) { alert('Select a primary and secondary type first.'); return }
    window.location.href = `/colo_result?${params.toString()}`
  })

  $('download-tsv').addEventListener('click', () => {
    const params = buildLinkParams()
    if (!params) { alert('Select a primary and secondary type first.'); return }
    params.set('format', 'tsv')
    window.location.href = `/api/colo/download?${params.toString()}`
  })

  $('download-gml').addEventListener('click', () => {
    const params = buildLinkParams()
    if (!params) { alert('Select a primary and secondary type first.'); return }
    params.set('format', 'gml')
    window.location.href = `/api/colo/download?${params.toString()}`
  })
}

document.addEventListener('DOMContentLoaded', init)
