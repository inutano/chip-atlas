// frontend/pages/target-genes-result.ts
// Fetches /api/target_genes and renders the gene x experiment score matrix.

import { getTargetGenesData } from '../api/client'

interface ExperimentRow {
  experiment_id: string
  cell_type: string
  cell_type_class: string
}

interface GeneRow {
  symbol: string
  avg_score: number
  scores: number[]
}

interface ResultData {
  genome: string
  track: string
  distance: string
  experiments: ExperimentRow[]
  genes: GeneRow[]
}

interface State {
  data: ResultData | null
  filter: string
  sortColumn: number  // -1 = avg, 0..N = experiment index
  sortDescending: boolean
}

const state: State = { data: null, filter: '', sortColumn: -1, sortDescending: true }

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readQueryParams(): { genome: string; track: string; distance: string } | null {
  const p = new URLSearchParams(window.location.search)
  const genome = p.get('genome')
  const track = p.get('track')
  const distance = p.get('distance')
  if (!genome || !track || !distance) return null
  return { genome, track, distance }
}

function renderHeader(data: ResultData): void {
  const thead = $('result-thead')
  const tr = document.createElement('tr')

  const symbolTh = document.createElement('th')
  symbolTh.scope = 'col'
  symbolTh.textContent = 'Gene'
  tr.appendChild(symbolTh)

  const avgTh = document.createElement('th')
  avgTh.scope = 'col'
  avgTh.style.cursor = 'pointer'
  avgTh.textContent = `Avg ${state.sortColumn === -1 ? (state.sortDescending ? '↓' : '↑') : ''}`
  avgTh.addEventListener('click', () => toggleSort(-1))
  tr.appendChild(avgTh)

  data.experiments.forEach((exp, i) => {
    const th = document.createElement('th')
    th.scope = 'col'
    th.style.cursor = 'pointer'
    th.title = `${exp.cell_type} (${exp.cell_type_class})`
    th.textContent = `${exp.experiment_id} ${state.sortColumn === i ? (state.sortDescending ? '↓' : '↑') : ''}`
    th.addEventListener('click', () => toggleSort(i))
    tr.appendChild(th)
  })

  thead.replaceChildren(tr)
}

function toggleSort(column: number): void {
  if (state.sortColumn === column) {
    state.sortDescending = !state.sortDescending
  } else {
    state.sortColumn = column
    state.sortDescending = true
  }
  if (state.data) renderRows(state.data)
  if (state.data) renderHeader(state.data)
}

function renderRows(data: ResultData): void {
  const filter = state.filter.toLowerCase()
  const filtered = filter
    ? data.genes.filter((g) => g.symbol.toLowerCase().includes(filter))
    : data.genes.slice()

  const sorted = filtered.sort((a, b) => {
    const av = state.sortColumn === -1 ? a.avg_score : (a.scores[state.sortColumn] ?? 0)
    const bv = state.sortColumn === -1 ? b.avg_score : (b.scores[state.sortColumn] ?? 0)
    return state.sortDescending ? bv - av : av - bv
  })

  const tbody = $('result-tbody')
  tbody.replaceChildren(...sorted.map((g) => {
    const tr = document.createElement('tr')

    const symbolTd = document.createElement('td')
    symbolTd.textContent = g.symbol
    tr.appendChild(symbolTd)

    const avgTd = document.createElement('td')
    avgTd.textContent = g.avg_score.toFixed(2)
    tr.appendChild(avgTd)

    g.scores.forEach((s) => {
      const td = document.createElement('td')
      td.textContent = s.toFixed(2)
      tr.appendChild(td)
    })
    return tr
  }))

  $('row-count').textContent = `${sorted.length.toLocaleString()} genes shown (of ${data.genes.length.toLocaleString()} total)`
}

function downloadTsv(): void {
  const params = readQueryParams()
  if (!params) return
  const url = `/api/target_genes/download?${new URLSearchParams({ ...params, format: 'tsv' }).toString()}`
  window.location.href = url
}

async function init(): Promise<void> {
  const params = readQueryParams()
  if (!params) {
    ;($('loading-state') as HTMLElement).hidden = true
    const err = $('error-state') as HTMLElement
    err.textContent = 'Missing genome, track, or distance parameter in URL.'
    err.hidden = false
    return
  }

  $('result-summary').textContent = `${params.track} on ${params.genome} (TSS ± ${params.distance} kb)`

  try {
    const data = await getTargetGenesData(params.genome, params.track, params.distance) as unknown as ResultData
    state.data = data
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = false
    renderHeader(data)
    renderRows(data)
  } catch (err) {
    console.error(err)
    ;($('loading-state') as HTMLElement).hidden = true
    const e = $('error-state') as HTMLElement
    e.textContent = 'Failed to load results. The data may not exist yet for this combination.'
    e.hidden = false
    return
  }

  ;($('gene-search') as HTMLInputElement).addEventListener('input', (e) => {
    state.filter = (e.target as HTMLInputElement).value
    if (state.data) renderRows(state.data)
  })

  $('download-tsv').addEventListener('click', downloadTsv)
}

document.addEventListener('DOMContentLoaded', init)
