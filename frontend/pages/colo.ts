// frontend/pages/colo.ts
// Colocalization setup: genome tabs + direction radio + primary/secondary autocomplete + submit/download.

import { GenomeTabs } from '../components/genome-tabs'
import { Autocomplete } from '../components/autocomplete'
import { getColoIndex, type ColoIndex, type ColoIndexEntry } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

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

export type ColoDirection = 'track' | 'cell_type'

/**
 * What the primary panel offers: every antigen, or every cell-type class,
 * depending on the search mode. It never depends on what is selected.
 */
export function primaryItemsFor(entry: ColoIndexEntry | undefined, direction: ColoDirection): string[] {
  if (!entry) return []
  return direction === 'track' ? Object.keys(entry.track) : Object.keys(entry.cell_type)
}

/**
 * What the secondary panel offers: the partners of the chosen primary, or —
 * before anything is chosen — everything this genome has, so the panel shows
 * the range on offer rather than an empty box.
 *
 * A primary that is not in the index (a stale value carried across a genome
 * switch, say) also falls back to everything rather than to nothing.
 */
export function secondaryItemsFor(
  entry: ColoIndexEntry | undefined,
  direction: ColoDirection,
  primary: string,
): string[] {
  if (!entry) return []
  const forward = direction === 'track'
  const index = forward ? entry.track : entry.cell_type
  const all = forward ? Object.keys(entry.cell_type) : Object.keys(entry.track)
  return (primary && index[primary]) || all
}

function getDirection(): ColoDirection {
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
  const data = readPageData()
  const pInput = $('primary-input') as HTMLInputElement
  const sInput = $('secondary-input') as HTMLInputElement

  // The two panels are refreshed separately on purpose. The primary panel's
  // contents depend only on the genome and the direction; the secondary's
  // also depend on what the primary is. Re-setting the primary's items when
  // only the secondary needed updating re-renders its list box, which drops
  // the visible selection back to the first row -- so choosing STAT3 left
  // the query correct but the list box sitting on AATF.
  function refreshPrimary(): void {
    Autocomplete.setItems(pInput, primaryItemsFor(coloIndex[currentGenome], getDirection()))
  }

  function refreshSecondary(): void {
    Autocomplete.setItems(
      sInput,
      secondaryItemsFor(coloIndex[currentGenome], getDirection(), currentPrimary),
    )
  }

  function refresh(): void {
    refreshPrimary()
    refreshSecondary()
  }

  Autocomplete.init(pInput, [], (value) => {
    currentPrimary = value
    // Whatever was chosen for the secondary belongs to the previous primary
    // and may not even be offered for this one -- clear it rather than carry
    // a stale pair into /colo_result.
    currentSecondary = ''
    sInput.value = ''
    refreshSecondary()
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

// Guarded (rather than a bare top-level call) so primaryItemsFor and
// secondaryItemsFor can be imported and unit-tested under plain Node, which
// has no `document` — the same pattern as enrichment-analysis.ts and
// colo-result.ts. It was missing here only because nothing in this file was
// exported to test while the picker was gated off.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
