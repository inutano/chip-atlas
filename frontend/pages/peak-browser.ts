// frontend/pages/peak-browser.ts
// Genome tabs + FacetFilter + IGV/Download actions.

import { GenomeTabs } from '../components/genome-tabs'
import { FacetFilter } from '../components/facet-filter'
import { getIgvUrl, getDownloadUrl, type UrlCondition } from '../api/client'

interface PageData {
  genomes: Record<string, string>
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

function buildCondition(facet: HTMLElement): UrlCondition | null {
  const c = FacetFilter.getCondition(facet)
  if (!c) return null
  return {
    genome: c.genome,
    track_class: c.track_class,
    track_subclass: c.track_subclass || undefined,
    cell_type_class: c.cell_type_class || undefined,
    cell_type_subclass: c.cell_type_subclass || undefined,
    qval: c.qval || undefined,
  }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const facet = $('facet-filter')
  const status = $('action-status')

  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    if (FacetFilter.getCondition(facet)) {
      await FacetFilter.setGenome(facet, detail.genome)
    } else {
      await FacetFilter.init(facet, detail.genome)
    }
  })

  GenomeTabs.init(tabs, data.genomes)

  $('view-igv').addEventListener('click', async () => {
    const condition = buildCondition(facet)
    if (!condition) { status.textContent = 'Select a track type first.'; return }
    status.textContent = 'Building IGV link…'
    try {
      const res = await getIgvUrl(condition)
      status.textContent = ''
      window.location.href = res.url
    } catch (err) {
      console.error(err)
      status.textContent = 'Failed to build IGV link.'
    }
  })

  $('download-bed').addEventListener('click', async () => {
    const condition = buildCondition(facet)
    if (!condition) { status.textContent = 'Select a track type first.'; return }
    status.textContent = 'Building download link…'
    try {
      const res = await getDownloadUrl(condition)
      status.textContent = ''
      window.location.href = res.url
    } catch (err) {
      console.error(err)
      status.textContent = 'Failed to build download link.'
    }
  })
}

document.addEventListener('DOMContentLoaded', init)
