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
// api/client.ts) can run long. Rather than letting a single wide cell force
// #result-table-wrap's horizontal scroll on an otherwise-narrow page, show a
// fixed-length window of the display string — centred on the first search
// hit when there is one, so a match past the old fixed 100-character
// truncation is no longer invisible — and let the row's own <details>
// expand to the full text.
export const ATTRIBUTES_WINDOW_LENGTH = 100

// D1: attributes are third-party metadata joined with a literal "__TAB__"
// marker for storage — replace it with a reader-facing separator for
// display. TSV export (toTsv below) keeps the raw value untouched.
export function formatAttributes(attributes: string): string {
  return attributes.split('__TAB__').join(' · ')
}

// R9: the terms to highlight in a result row, derived from the search box
// query. Mirrors ChipAtlas::ExperimentSearch.match_expression's tokenisation
// (lib/models/experiment_search.rb) exactly — whitespace-split, "quoted
// phrases" kept whole, the FTS5 metacharacters " ' ( ) * ^ { } : stripped
// from each term, empty terms dropped — so the terms highlighted here are
// the same terms the server matched on. Unlike match_expression, this does
// not quote terms or append the "*" prefix operator: this list is used to
// find and highlight plain text, not to build a MATCH expression.
export function searchTerms(query: string): string[] {
  const terms: string[] = []
  const trimmed = query.trim()
  const pattern = /"([^"]*)"|(\S+)/g
  let match: RegExpExecArray | null
  while ((match = pattern.exec(trimmed)) !== null) {
    const raw = match[1] !== undefined ? match[1] : match[2]
    const cleaned = raw.replace(/["'()*^{}:]/g, '').trim()
    if (cleaned) terms.push(cleaned)
  }
  return terms
}

// Longest of `terms` (already lower-cased) that matches `lower` starting
// exactly at `index`, or 0 if none does. Shared by firstHit (below) and
// highlightSegments so both agree on the same "longest term wins, matches
// never overlap" rule at a given position.
function longestMatchAt(lower: string, lowerTerms: string[], index: number): number {
  let best = 0
  for (const term of lowerTerms) {
    if (term.length > best && lower.startsWith(term, index)) {
      best = term.length
    }
  }
  return best
}

// The earliest case-insensitive occurrence of any of `terms` in `formatted`,
// with the length of whichever term matched there (the longest, if more
// than one term matches at that exact position) — or null if none occurs.
function firstHit(formatted: string, terms: string[]): { index: number; length: number } | null {
  const lowerTerms = terms.filter((t) => t.length > 0).map((t) => t.toLowerCase())
  if (lowerTerms.length === 0) return null
  const lower = formatted.toLowerCase()
  for (let i = 0; i < lower.length; i++) {
    const length = longestMatchAt(lower, lowerTerms, i)
    if (length > 0) return { index: i, length }
  }
  return null
}

// Earliest case-insensitive occurrence of any term in `formatted`, or -1.
export function firstHitIndex(formatted: string, terms: string[]): number {
  const hit = firstHit(formatted, terms)
  return hit ? hit.index : -1
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
}

// A fixed-length window into `formatted`, centred on the first search hit:
//   1. formatted fits within `length` already -> return it unchanged.
//   2. no hit -> the head of the string (today's behaviour before R9).
//   3. otherwise centre the window on the hit, clamped to the string's
//      bounds, with a leading/trailing '…' exactly where text was cut.
export function attributesWindow(
  formatted: string,
  terms: string[],
  length: number = ATTRIBUTES_WINDOW_LENGTH
): string {
  if (formatted.length <= length) return formatted

  const hit = firstHit(formatted, terms)
  if (!hit) return formatted.slice(0, length) + '…'

  const start = clamp(hit.index - Math.floor((length - hit.length) / 2), 0, formatted.length - length)
  const end = start + length
  const prefix = start > 0 ? '…' : ''
  const suffix = end < formatted.length ? '…' : ''
  return prefix + formatted.slice(start, end) + suffix
}

// Splits `text` into alternating plain/hit segments covering the whole
// string, so the caller can wrap hits in <mark> using createElement/
// textContent (never innerHTML). Matching is case-insensitive; at a given
// position the longest matching term wins and matches never overlap. No
// terms (e.g. an empty query) -> the whole text as a single plain segment.
export function highlightSegments(text: string, terms: string[]): Array<{ text: string; hit: boolean }> {
  const lowerTerms = terms.filter((t) => t.length > 0).map((t) => t.toLowerCase())
  if (lowerTerms.length === 0) return [{ text, hit: false }]

  const lower = text.toLowerCase()
  const segments: Array<{ text: string; hit: boolean }> = []
  let plainStart = 0
  let i = 0
  while (i < text.length) {
    const length = longestMatchAt(lower, lowerTerms, i)
    if (length > 0) {
      if (i > plainStart) segments.push({ text: text.slice(plainStart, i), hit: false })
      segments.push({ text: text.slice(i, i + length), hit: true })
      i += length
      plainStart = i
    } else {
      i += 1
    }
  }
  if (plainStart < text.length) segments.push({ text: text.slice(plainStart), hit: false })
  return segments
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

// Appends `text` to `parent` as alternating plain text nodes and <mark>
// elements (per highlightSegments), built with createElement/textContent —
// never innerHTML, since attribute text is third-party metadata.
function appendHighlighted(parent: HTMLElement, text: string, terms: string[]): void {
  for (const segment of highlightSegments(text, terms)) {
    if (segment.hit) {
      const mark = document.createElement('mark')
      mark.textContent = segment.text
      parent.appendChild(mark)
    } else {
      parent.appendChild(document.createTextNode(segment.text))
    }
  }
}

// R9: show the Dataset Search hit in context, with one click-to-expand
// control instead of duplicating the head of the string. When the formatted
// text already fits within the window, render it plain (hit-marked), as
// before. Otherwise render a window centred on the first hit inside
// <summary>, and the full text (also hit-marked) inside the <details> body —
// the two are never both visible: opening swaps the window for "Show less"
// (see the details[open] CSS rules), and the full text appears once.
function renderAttributesCell(attributes: string, terms: string[]): HTMLTableCellElement {
  const td = document.createElement('td')
  td.className = 'search-attrs-cell'
  const formatted = formatAttributes(attributes)
  if (formatted.length <= ATTRIBUTES_WINDOW_LENGTH) {
    appendHighlighted(td, formatted, terms)
    return td
  }

  const details = document.createElement('details')
  const summary = document.createElement('summary')

  const windowSpan = document.createElement('span')
  windowSpan.className = 'search-attrs-window'
  appendHighlighted(windowSpan, attributesWindow(formatted, terms), terms)
  summary.appendChild(windowSpan)

  const lessSpan = document.createElement('span')
  lessSpan.className = 'search-attrs-less'
  lessSpan.textContent = 'Show less'
  summary.appendChild(lessSpan)

  details.appendChild(summary)

  const full = document.createElement('div')
  full.className = 'search-attrs-full'
  appendHighlighted(full, formatted, terms)
  details.appendChild(full)

  td.appendChild(details)
  return td
}

function renderRow(row: SearchExperiment, terms: string[]): HTMLTableRowElement {
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

  tr.appendChild(renderAttributesCell(row.attributes || '', terms))

  return tr
}

function renderResults(result: SearchResult): void {
  state.lastResult = result

  const terms = searchTerms(state.query)
  const tbody = $('search-tbody')
  tbody.replaceChildren(...result.experiments.map((row) => renderRow(row, terms)))

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

// Guarded so the pure functions above (formatAttributes, searchTerms,
// firstHitIndex, attributesWindow, highlightSegments, geoAccUrl) can be
// imported and unit-tested under plain Node, which has no `document` — see
// search.test.ts, and colo-result.ts / target-genes-result.ts / peak-browser.ts
// for the same pattern.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
