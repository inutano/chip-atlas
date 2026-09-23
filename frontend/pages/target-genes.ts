// frontend/pages/target-genes.ts
// Target Genes setup: genome tabs + antigen autocomplete + distance radio + submit/download.

import { GenomeTabs } from '../components/genome-tabs'
import { Autocomplete } from '../components/autocomplete'
import { getTargetGenesIndex, type TargetGenesIndex } from '../api/client'

interface PageData {
  genomes: Record<string, string>
}

let currentGenome = ''
let currentTrack = ''
let allTracks: TargetGenesIndex = {}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function getDistance(): string {
  const checked = document.querySelector<HTMLInputElement>('input[name="distance"]:checked')
  return checked?.value || '1'
}

async function init(): Promise<void> {
  const data = readPageData()

  try {
    allTracks = await getTargetGenesIndex()
  } catch (err) {
    console.warn('Failed to load target genes index:', err)
  }

  const tabsContainer = $('genome-tabs')
  tabsContainer.addEventListener('genome-change', (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
    // Clear before repopulating, not after: Autocomplete.setItems only fires
    // its auto-selection sync (TG-09) when the input is empty at the time it
    // runs, so currentTrack ends up set to the new genome's first antigen
    // instead of being wiped back to '' by these two lines a moment later.
    currentTrack = ''
    trackInput.value = ''
    const tracks = allTracks[currentGenome] || []
    Autocomplete.setItems(trackInput, tracks)
  })

  const trackInput = $('track-input') as HTMLInputElement
  Autocomplete.init(trackInput, [], (value) => {
    currentTrack = value
  }, { pairedList: $('antigen-list') })

  GenomeTabs.init(tabsContainer, data.genomes)

  $('view-target-genes').addEventListener('click', () => {
    if (!currentGenome || !currentTrack) {
      alert('Select a genome and antigen first.')
      return
    }
    const params = new URLSearchParams({ genome: currentGenome, track: currentTrack, distance: getDistance() })
    window.location.href = `/target_genes_result?${params.toString()}`
  })

  $('download-tsv').addEventListener('click', () => {
    if (!currentGenome || !currentTrack) {
      alert('Select a genome and antigen first.')
      return
    }
    const params = new URLSearchParams({
      genome: currentGenome, track: currentTrack, distance: getDistance(), format: 'tsv',
    })
    window.location.href = `/api/target_genes/download?${params.toString()}`
  })
}

document.addEventListener('DOMContentLoaded', init)
