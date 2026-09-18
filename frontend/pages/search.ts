// frontend/pages/search.ts
// Server-side paginated search. Replaces the legacy DataTables + 200MB JSON.

import { listGenomes, searchExperiments, type SearchExperiment, type SearchResult } from '../api/client'

const PAGE_SIZE = 20

const HEADERS = [
  'SRX', 'SRA', 'GEO', 'Genome', 'Track class', 'Track type', 'Cell type class', 'Cell type',
  'Title', 'Attributes',
] as const

// Attributes strings (a single string of key=value pairs joined by
// "__TAB__" — see the SearchExperiment.attributes doc comment in
// api/client.ts) can run long. Truncate the on-page display and let the
// row's own <details> expand it, rather than letting a single wide cell
// force #result-table-wrap's horizontal scroll on an otherwise-narrow page.
const ATTRIBUTES_TRUNCATE_LENGTH = 100

// D1: attributes are third-party metadata joined with a literal "__TAB__"
// marker for storage — replace it with a reader-facing separator for
// display. TSV export (toTsv below) keeps the raw value untouched.
export function formatAttributes(attributes: string): string {
  return attributes.split('__TAB__').join(' · ')
}

// D3: any non-"-" GEO id links out to NCBI GEO; "-" (or empty) means "no
// GEO record for this experiment" and stays plain text.
export function geoAccUrl(geoId: string): string | null {
  if (!geoId || geoId === '-') return null
  return `https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=${encodeURIComponent(geoId)}`
}

interface State {
  query: string
  genome: string
  offset: number
  lastResult: SearchResult | null
}

const state: State = { query: '', genome: '', offset: 0, lastResult: null }

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

async function populateGenomeOptions(): Promise<void> {
  try {
    const genomes = await listGenomes()
    const select = $('search-genome') as HTMLSelectElement
    for (const [code, label] of Object.entries(genomes)) {
      const opt = document.createElement('option')
      opt.value = code
      opt.textContent = `${code} — ${label}`
      select.appendChild(opt)
    }
  } catch (err) {
    console.warn('Failed to load genomes:', err)
  }
}

function renderGeoCell(geoId: string): HTMLTableCellElement {
  const td = document.createElement('td')
  const url = geoAccUrl(geoId)
  if (url) {
    const link = document.createElement('a')
    link.href = url
    link.textContent = geoId
    link.target = '_blank'
    link.rel = 'noopener noreferrer'
    td.appendChild(link)
  } else {
    td.textContent = geoId || ''
  }
  return td
}

function renderAttributesCell(attributes: string): HTMLTableCellElement {
  const td = document.createElement('td')
  td.className = 'search-attrs-cell'
  const formatted = formatAttributes(attributes)
  if (formatted.length <= ATTRIBUTES_TRUNCATE_LENGTH) {
    td.textContent = formatted
    return td
  }

  const details = document.createElement('details')
  const summary = document.createElement('summary')
  summary.textContent = formatted.slice(0, ATTRIBUTES_TRUNCATE_LENGTH) + '…'
  details.appendChild(summary)

  const full = document.createElement('div')
  full.className = 'search-attrs-full'
  full.textContent = formatted
  details.appendChild(full)

  td.appendChild(details)
  return td
}

function renderRow(row: SearchExperiment): HTMLTableRowElement {
  const tr = document.createElement('tr')

  const srxCell = document.createElement('td')
  const link = document.createElement('a')
  link.href = `/view?id=${encodeURIComponent(row.experiment_id)}`
  link.textContent = row.experiment_id
  link.className = 'expid-link'
  link.target = '_blank'
  link.rel = 'noopener noreferrer'
  srxCell.appendChild(link)
  tr.appendChild(srxCell)

  const sraCell = document.createElement('td')
  sraCell.textContent = row.sra_id || ''
  tr.appendChild(sraCell)

  tr.appendChild(renderGeoCell(row.geo_id))

  const fields: Array<keyof SearchExperiment> = [
    'genome', 'track_class', 'track_subclass', 'cell_type_class', 'cell_type_subclass',
  ]
  for (const f of fields) {
    const td = document.createElement('td')
    td.textContent = row[f] || ''
    tr.appendChild(td)
  }

  const titleCell = document.createElement('td')
  titleCell.className = 'search-title-cell'
  titleCell.textContent = row.title || ''
  tr.appendChild(titleCell)

  tr.appendChild(renderAttributesCell(row.attributes || ''))

  return tr
}

function renderResults(result: SearchResult): void {
  state.lastResult = result

  const tbody = $('search-tbody')
  tbody.replaceChildren(...result.experiments.map(renderRow))

  const label = result.total === 0
    ? 'No entries found'
    : `Showing ${state.offset + 1} to ${state.offset + result.returned} of ${result.total.toLocaleString()} entries`
  $('search-count').textContent = label

  $('page-indicator').textContent = `Page ${Math.floor(state.offset / PAGE_SIZE) + 1} of ${Math.max(1, Math.ceil(result.total / PAGE_SIZE))}`

  const prevDisabled = state.offset === 0
  const nextDisabled = state.offset + result.returned >= result.total

  $('page-prev').classList.toggle('disabled', prevDisabled)
  $('page-next').classList.toggle('disabled', nextDisabled)

  const prevAnchor = $('page-prev').querySelector('a')
  const nextAnchor = $('page-next').querySelector('a')
  if (prevAnchor) {
    prevAnchor.setAttribute('aria-disabled', String(prevDisabled))
    prevAnchor.tabIndex = prevDisabled ? -1 : 0
  }
  if (nextAnchor) {
    nextAnchor.setAttribute('aria-disabled', String(nextDisabled))
    nextAnchor.tabIndex = nextDisabled ? -1 : 0
  }

  ;($('search-results-wrap') as HTMLElement).hidden = false
}

let searchGeneration = 0

async function runSearch(): Promise<void> {
  const status = $('search-status')
  status.textContent = 'Searching…'
  const gen = ++searchGeneration
  try {
    const result = await searchExperiments(state.query, state.genome || undefined, PAGE_SIZE, state.offset)
    if (gen !== searchGeneration) return  // stale response — newer search already in flight
    status.textContent = ''
    renderResults(result)
  } catch (err) {
    if (gen !== searchGeneration) return
    console.error(err)
    status.textContent = 'Search failed. Please try again.'
  }
}

function toTsv(rows: SearchExperiment[]): string {
  const lines = [HEADERS.join('\t')]
  for (const r of rows) {
    lines.push([
      r.experiment_id, r.sra_id, r.geo_id, r.genome,
      r.track_class, r.track_subclass, r.cell_type_class, r.cell_type_subclass,
      r.title, r.attributes,
    ].join('\t'))
  }
  return lines.join('\n') + '\n'
}

async function clipboardWrite(text: string): Promise<void> {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text)
  }
  const ta = document.createElement('textarea')
  ta.value = text
  ta.style.position = 'fixed'
  ta.style.left = '-9999px'
  document.body.appendChild(ta)
  ta.focus()
  ta.select()
  try { document.execCommand('copy') } catch (_) {}
  document.body.removeChild(ta)
}

async function copyResultsToClipboard(): Promise<void> {
  if (!state.lastResult) return
  const tsv = toTsv(state.lastResult.experiments)
  try {
    await clipboardWrite(tsv)
    const btn = $('copy-results')
    const original = btn.textContent || 'Copy'
    btn.textContent = 'Copied!'
    setTimeout(() => { btn.textContent = original }, 1500)
  } catch (err) {
    console.warn('Clipboard write failed:', err)
  }
}

function downloadTsv(): void {
  if (!state.lastResult) return
  const blob = new Blob([toTsv(state.lastResult.experiments)], { type: 'text/tab-separated-values' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `chip-atlas-search.tsv`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

function init(): void {
  populateGenomeOptions()
  runSearch()  // load the full, unfiltered listing on page load (mirrors production)

  const form = $('search-form') as HTMLFormElement
  form.addEventListener('submit', (e) => {
    e.preventDefault()
    state.query = ($('search-query') as HTMLInputElement).value
    state.genome = ($('search-genome') as HTMLSelectElement).value
    state.offset = 0
    runSearch()
  })

  $('page-prev').addEventListener('click', (e) => {
    e.preventDefault()
    if ($('page-prev').classList.contains('disabled')) return
    state.offset = Math.max(0, state.offset - PAGE_SIZE)
    runSearch()
  })
  $('page-next').addEventListener('click', (e) => {
    e.preventDefault()
    if ($('page-next').classList.contains('disabled')) return
    state.offset += PAGE_SIZE
    runSearch()
  })

  $('copy-results').addEventListener('click', copyResultsToClipboard)
  $('download-tsv').addEventListener('click', downloadTsv)
}

// Guarded so the pure functions above (formatAttributes, geoAccUrl) can be
// imported and unit-tested under plain Node, which has no `document` — see
// search.test.ts, and colo-result.ts / target-genes-result.ts / peak-browser.ts
// for the same pattern.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
