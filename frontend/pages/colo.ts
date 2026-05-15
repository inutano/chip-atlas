// frontend/pages/colo.ts
// Colocalization setup: genome tabs + direction radio + primary/secondary autocomplete + submit/download.

import { GenomeTabs } from '../components/genome-tabs'
import { Autocomplete } from '../components/autocomplete'
import { getColoIndex, type ColoIndex } from '../api/client'

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

function getDirection(): 'track' | 'cell_type' {
  const r = document.querySelector<HTMLInputElement>('input[name="direction"]:checked')
  return r?.value === 'cell_type' ? 'cell_type' : 'track'
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
  })
  Autocomplete.init(sInput, [], (value) => {
    currentSecondary = value
  })

  document.querySelectorAll<HTMLInputElement>('input[name="direction"]').forEach((r) => {
    r.addEventListener('change', () => {
      currentPrimary = ''
      currentSecondary = ''
      pInput.value = ''
      sInput.value = ''
      refresh()
    })
  })

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
