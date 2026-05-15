// frontend/pages/colo-result.ts
// Fetches /api/colo and renders the colocalization partners table.

import { getColoData } from '../api/client'

interface Partner {
  experiment_id: string
  track: string
  cell_type: string
  cell_type_class: string
  score: number
  shared_bins: number
}

interface ResultData {
  genome: string
  track: string
  cell_type: string
  partners: Partner[]
}

interface State {
  data: ResultData | null
  filter: string
}

const state: State = { data: null, filter: '' }

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readQueryParams(): { genome: string; track: string; cell_type: string } | null {
  const p = new URLSearchParams(window.location.search)
  const genome = p.get('genome')
  const track = p.get('track')
  const cell_type = p.get('cell_type')
  if (!genome || !track || !cell_type) return null
  return { genome, track, cell_type }
}

function renderRows(data: ResultData): void {
  const filter = state.filter.toLowerCase()
  const filtered = filter
    ? data.partners.filter((p) =>
        p.track.toLowerCase().includes(filter) || p.cell_type.toLowerCase().includes(filter))
    : data.partners

  const tbody = $('result-tbody')
  tbody.replaceChildren(...filtered.map((p, i) => {
    const tr = document.createElement('tr')

    const rankTd = document.createElement('td')
    rankTd.textContent = String(i + 1)
    tr.appendChild(rankTd)

    const trackTd = document.createElement('td')
    trackTd.textContent = p.track
    tr.appendChild(trackTd)

    const cellTd = document.createElement('td')
    cellTd.textContent = p.cell_type
    tr.appendChild(cellTd)

    const classTd = document.createElement('td')
    classTd.textContent = p.cell_type_class
    tr.appendChild(classTd)

    const scoreTd = document.createElement('td')
    scoreTd.textContent = p.score.toFixed(2)
    tr.appendChild(scoreTd)

    const binsTd = document.createElement('td')
    binsTd.textContent = p.shared_bins.toLocaleString()
    tr.appendChild(binsTd)

    const expTd = document.createElement('td')
    const link = document.createElement('a')
    link.href = `/view?id=${encodeURIComponent(p.experiment_id)}`
    link.textContent = p.experiment_id
    expTd.appendChild(link)
    tr.appendChild(expTd)

    return tr
  }))

  $('row-count').textContent = `${filtered.length.toLocaleString()} partners shown (of ${data.partners.length.toLocaleString()} total)`
}

function downloadFile(format: 'tsv' | 'gml'): void {
  const params = readQueryParams()
  if (!params) return
  const search = new URLSearchParams({ ...params, format })
  window.location.href = `/api/colo/download?${search.toString()}`
}

async function init(): Promise<void> {
  const params = readQueryParams()
  if (!params) {
    ;($('loading-state') as HTMLElement).hidden = true
    const e = $('error-state') as HTMLElement
    e.textContent = 'Missing genome, track, or cell_type parameter in URL.'
    e.hidden = false
    return
  }

  $('result-summary').textContent = `${params.track} (${params.cell_type}) on ${params.genome}`

  try {
    const data = await getColoData(params.genome, params.track, params.cell_type) as unknown as ResultData
    state.data = data
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = false
    renderRows(data)
  } catch (err) {
    console.error(err)
    ;($('loading-state') as HTMLElement).hidden = true
    const e = $('error-state') as HTMLElement
    e.textContent = 'Failed to load colocalization data.'
    e.hidden = false
    return
  }

  ;($('partner-search') as HTMLInputElement).addEventListener('input', (e) => {
    state.filter = (e.target as HTMLInputElement).value
    if (state.data) renderRows(state.data)
  })

  $('download-tsv').addEventListener('click', () => downloadFile('tsv'))
  $('download-gml').addEventListener('click', () => downloadFile('gml'))
}

document.addEventListener('DOMContentLoaded', init)
