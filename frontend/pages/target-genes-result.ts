// frontend/pages/target-genes-result.ts
// Fetches /api/target_genes and renders it as a gene x experiment score
// matrix, paginated over rows (genes) the way B2's server already slices
// them. Columns (experiments) are never paginated — the server always
// returns every column for the requested page of rows — so "genome/track"
// query row 0 through N is the only trip to the network; showing or hiding
// experiment columns is a pure display toggle over data already in memory.
//
// The result set can be 13,459 rows x 134+ columns (mm10/Stat3.1), so this
// module never asks for more than one page of rows (PAGE_SIZE, capped by
// the server's own MAX_LIMIT) and never renders the full 13,459-row matrix
// at once.

import { ApiError, getTargetGenesData, type TargetGenesResult } from '../api/client'

const PAGE_SIZE = 100
const AVERAGE_SUFFIX = '|Average'
const STRING_COLUMN = 'STRING'
const QUERY_DEBOUNCE_MS = 300

interface Params {
  genome: string
  track: string
  distance: string
}

interface State {
  genome: string
  track: string
  distance: string
  sort: string | null    // exact column header to sort by; null = server default (the Average column)
  order: 'asc' | 'desc'
  offset: number
  query: string          // gene-name filter, sent to the server as `q`; '' = no filter
  data: TargetGenesResult | null
}

const state: State = {
  genome: '', track: '', distance: '1', sort: null, order: 'desc', offset: 0, query: '', data: null,
}

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readQueryParams(): Params | null {
  const p = new URLSearchParams(window.location.search)
  const genome = p.get('genome')
  const track = p.get('track')
  if (!genome || !track) return null
  const distance = p.get('distance') || '1'
  return { genome, track, distance }
}

function updateUrl(): void {
  const params = new URLSearchParams({ genome: state.genome, track: state.track, distance: state.distance })
  const url = `${window.location.pathname}?${params.toString()}`
  window.history.replaceState(null, '', url)
}

// ===== Score -> color (matches production's MACS2/STRING legend) =====
// 0 is a distinct gray (no signal); 1..1000 interpolates blue -> cyan ->
// green -> yellow -> red; anything above 1000 clamps to red.
const COLOR_STOPS: Array<[number, [number, number, number]]> = [
  [1, [0, 0, 255]],
  [250, [0, 255, 255]],
  [500, [0, 255, 0]],
  [750, [255, 255, 0]],
  [1000, [255, 0, 0]],
]

function scoreToRgb(value: number): [number, number, number] {
  if (value <= 0) return [128, 128, 128]
  if (value >= 1000) return [255, 0, 0]
  for (let i = 0; i < COLOR_STOPS.length - 1; i++) {
    const [v0, c0] = COLOR_STOPS[i]
    const [v1, c1] = COLOR_STOPS[i + 1]
    if (value >= v0 && value <= v1) {
      const t = (value - v0) / (v1 - v0)
      return [
        Math.round(c0[0] + (c1[0] - c0[0]) * t),
        Math.round(c0[1] + (c1[1] - c0[1]) * t),
        Math.round(c0[2] + (c1[2] - c0[2]) * t),
      ]
    }
  }
  return [128, 128, 128]
}

function rgbToHex([r, g, b]: [number, number, number]): string {
  return `#${[r, g, b].map((x) => x.toString(16).padStart(2, '0')).join('')}`
}

function readableTextColor([r, g, b]: [number, number, number]): string {
  const luminance = 0.299 * r + 0.587 * g + 0.114 * b
  return luminance > 140 ? '#000' : '#fff'
}

function formatScore(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2)
}

// ===== Column bookkeeping =====

function averageColumnIndex(columns: string[]): number {
  const idx = columns.findIndex((c) => c.endsWith(AVERAGE_SUFFIX))
  return idx === -1 ? 1 : idx
}

function stringColumnIndex(columns: string[]): number {
  const idx = columns.indexOf(STRING_COLUMN)
  return idx === -1 ? columns.length - 1 : idx
}

// Splits an experiment column header ("SRX361677|Astrocytes") into its
// experiment id and cell type. Falls back to treating the whole header as
// the id if it doesn't contain the separator (defensive — headers are
// server data, not guaranteed to match the usual shape forever).
function splitExperimentHeader(header: string): { experimentId: string; cellType: string } {
  const sep = header.indexOf('|')
  if (sep === -1) return { experimentId: header, cellType: '' }
  return { experimentId: header.slice(0, sep), cellType: header.slice(sep + 1) }
}

// ===== Sort state transitions (pure — unit-tested directly, see
// target-genes-result.test.ts) =====
//
// Both the mouse click handler and a keyboard Enter/Space activation of a
// header's <button> fire the exact same DOM "click" event (that equivalence
// is guaranteed by the HTML spec for <button> elements, not something this
// module implements itself), so a single click handler correctly covers
// both input methods as long as the header is a real, focusable <button>
// rather than a plain <th> with a click listener (a <th> is not natively
// focusable or keyboard-operable — that was the bug).

export interface SortState {
  sort: string | null
  order: 'asc' | 'desc'
}

// Clicking (by mouse or keyboard) the currently-sorted column's header
// flips direction; clicking a different column switches to it, descending
// first — matching the server's own default when no sort/order is given.
export function computeNextSort(current: SortState, column: string): SortState {
  if (current.sort === column) {
    return { sort: column, order: current.order === 'desc' ? 'asc' : 'desc' }
  }
  return { sort: column, order: 'desc' }
}

// aria-sort for a given column header, per the WAI-ARIA APG sortable-table
// pattern: "ascending"/"descending" on the currently-sorted column, "none"
// on every other sortable column.
export function computeAriaSort(current: SortState, column: string): 'ascending' | 'descending' | 'none' {
  if (current.sort !== column) return 'none'
  return current.order === 'desc' ? 'descending' : 'ascending'
}

// True when `err` is the 400 TargetGenesTsv::UnknownSortColumn response
// (routes/api.rb) — i.e. the retained sort column doesn't exist in the
// column set that was just fetched (this happens across a distance switch:
// see the fallback in `load()`). Only meaningful when a sort is actually
// set; a 400 with no active sort would indicate a different bug.
export function isUnknownSortColumnError(err: unknown): boolean {
  return err instanceof ApiError && err.status === 400
}

// ===== Rendering =====

function sortArrowGlyph(column: string): string {
  if (state.sort !== column) return ''
  return state.order === 'desc' ? '↓' : '↑'
}

function sortStateHint(column: string): string {
  if (state.sort !== column) return ''
  return state.order === 'desc' ? ' (sorted descending)' : ' (sorted ascending)'
}

function handleSortClick(column: string): void {
  const next = computeNextSort(state, column)
  state.sort = next.sort
  state.order = next.order
  state.offset = 0
  void load()
}

// Builds a sortable <th> containing a real <button> — focusable, the
// correct implicit role, and Enter/Space already work because that's how
// every <button> behaves. `label` is the button's visible + accessible
// text; callers needing extra markup (the experiment columns' outbound
// /view link) append it to the returned <th> afterwards, as a sibling of
// the button rather than nested inside it (a link nested inside a button
// is invalid HTML and unreachable by keyboard).
function makeSortableHeader(label: string, sortColumn: string, extraClass?: string): HTMLTableCellElement {
  const th = document.createElement('th')
  th.scope = 'col'
  if (extraClass) th.className = extraClass
  th.classList.add('tg-sortable')
  th.setAttribute('aria-sort', computeAriaSort(state, sortColumn))

  const btn = document.createElement('button')
  btn.type = 'button'
  btn.className = 'tg-sort-btn'
  btn.appendChild(document.createTextNode(label))

  const arrow = document.createElement('span')
  arrow.className = 'tg-sort-indicator'
  arrow.setAttribute('aria-hidden', 'true')
  arrow.textContent = sortArrowGlyph(sortColumn) ? ` ${sortArrowGlyph(sortColumn)}` : ''
  btn.appendChild(arrow)

  // Redundant with aria-sort on the <th>, but screen readers vary in
  // whether they surface an ancestor's aria-sort when focus lands directly
  // on a nested control (as it does here, via Tab) rather than via table
  // navigation commands — so also say it plainly, visually hidden.
  const hint = document.createElement('span')
  hint.className = 'visually-hidden'
  hint.textContent = sortStateHint(sortColumn)
  btn.appendChild(hint)

  btn.addEventListener('click', () => handleSortClick(sortColumn))
  th.appendChild(btn)
  return th
}

function renderHeader(data: TargetGenesResult): void {
  const row = $('result-thead-row')
  const avgIdx = averageColumnIndex(data.columns)
  const strIdx = stringColumnIndex(data.columns)

  const cells: HTMLTableCellElement[] = []

  data.columns.forEach((col, i) => {
    if (i === 0) {
      cells.push(makeSortableHeader('Gene', col))
      return
    }
    if (i === avgIdx) {
      const th = makeSortableHeader('Average', col)
      th.title = col.replace('|', ' | ')
      cells.push(th)
      return
    }
    if (i === strIdx) {
      cells.push(makeSortableHeader('STRING', col))
      return
    }

    // An experiment column, grouped under the Average column and hidden
    // until "Show experiment columns" is expanded. Built from the same
    // sortable-header helper as Gene/Average/STRING; the outbound /view
    // link is appended afterwards as a sibling of the sort button, not
    // nested inside it (see makeSortableHeader's comment).
    const { experimentId, cellType } = splitExperimentHeader(col)
    const label = cellType ? `${experimentId}: ${cellType}` : experimentId
    const th = makeSortableHeader(label, col, 'tg-exp-col')
    th.title = label

    const link = document.createElement('a')
    link.className = 'tg-exp-link'
    link.href = `/view?id=${encodeURIComponent(experimentId)}`
    link.textContent = '↗'
    link.setAttribute('aria-label', `View experiment ${experimentId}`)
    th.appendChild(link)

    cells.push(th)
  })

  row.replaceChildren(...cells)
}

function scoreCell(value: number, extraClass?: string): HTMLTableCellElement {
  const td = document.createElement('td')
  td.className = extraClass ? `tg-score-cell ${extraClass}` : 'tg-score-cell'
  const rgb = scoreToRgb(value)
  td.style.backgroundColor = rgbToHex(rgb)
  td.style.color = readableTextColor(rgb)
  td.textContent = formatScore(value)
  return td
}

function renderRows(data: TargetGenesResult): void {
  const avgIdx = averageColumnIndex(data.columns)
  const strIdx = stringColumnIndex(data.columns)

  const tbody = $('result-tbody')
  tbody.replaceChildren(...data.rows.map((row) => {
    const tr = document.createElement('tr')

    row.forEach((value, i) => {
      if (i === 0) {
        const td = document.createElement('td')
        td.textContent = String(value)
        tr.appendChild(td)
        return
      }
      const numeric = typeof value === 'number' ? value : Number(value)
      if (i === avgIdx || i === strIdx) {
        tr.appendChild(scoreCell(numeric))
        return
      }
      tr.appendChild(scoreCell(numeric, 'tg-exp-col'))
    })

    return tr
  }))
}

// Two distinct empty facts, deliberately worded differently so neither is
// mistaken for the other (see the module comment on the old client-side
// filter this replaces): a `total` of 0 while a gene-name filter is active
// means "no gene matches your text" - the data is there, the query just
// didn't hit anything - versus (handled entirely in load()'s catch block,
// not here) "this antigen/genome/distance combination has no precomputed
// data at all", which is a fetch failure, not a filtered-down zero.
// Exported (and taking `query` as a plain argument rather than reading
// module state) so it's unit-testable the same way as computeNextSort /
// computeAriaSort / isUnknownSortColumnError above - see
// target-genes-result.test.ts. Callers must assign the result via
// textContent, never innerHTML: `query` is untrusted user input.
export function emptyStateMessage(query: string): string {
  return query
    ? `No genes match "${query}".`
    : 'No target genes found'
}

function renderPagination(data: TargetGenesResult): void {
  const shown = data.rows.length
  $('row-count').textContent = data.total === 0
    ? emptyStateMessage(state.query)
    : `Showing ${data.offset + 1} to ${data.offset + shown} of ${data.total.toLocaleString()} genes`

  const totalPages = Math.max(1, Math.ceil(data.total / PAGE_SIZE))
  const currentPage = Math.floor(data.offset / PAGE_SIZE) + 1
  $('page-indicator').textContent = `Page ${currentPage} of ${totalPages}`

  const prevDisabled = data.offset === 0
  const nextDisabled = data.offset + shown >= data.total

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
}

function updateExperimentsToggleLabel(data: TargetGenesResult): void {
  const experimentCount = data.columns.length - 3 // Target_genes, Average, STRING are never counted as experiments
  const summary = $('experiments-toggle-summary')
  const details = $('experiments-toggle') as HTMLDetailsElement
  summary.textContent = details.open
    ? `Hide experiment columns (${experimentCount.toLocaleString()})`
    : `Show experiment columns (${experimentCount.toLocaleString()})`
}

function updateDistanceButtons(): void {
  document.querySelectorAll<HTMLButtonElement>('#distance-switch button[data-distance]').forEach((btn) => {
    const active = btn.dataset.distance === state.distance
    btn.classList.toggle('active', active)
    btn.setAttribute('aria-pressed', String(active))
  })
}

function updateDownloadLink(): void {
  const link = $('download-tsv') as HTMLAnchorElement
  const params = new URLSearchParams({
    genome: state.genome, track: state.track, distance: state.distance, format: 'tsv',
  })
  link.href = `/api/target_genes/download?${params.toString()}`
  link.hidden = false
}

function setSummary(): void {
  $('result-summary').textContent = `${state.track} on ${state.genome} — TSS ± ${state.distance} kb`
}

function hideSortFallbackNote(): void {
  ;($('sort-fallback-note') as HTMLElement).hidden = true
}

function showSortFallbackNote(previousSort: string): void {
  const note = $('sort-fallback-note') as HTMLElement
  note.textContent = `"${previousSort}" isn't a column at this distance — sorted by the default Average column instead.`
  note.hidden = false
}

let loadGeneration = 0

// `isFallbackRetry` is set only on the one retry triggered below, so a sort
// column that's *still* unknown after being reset to null (which should be
// unreachable — null means "let the server pick its own default") can't
// loop forever.
async function load(isFallbackRetry = false): Promise<void> {
  const gen = ++loadGeneration
  ;($('loading-state') as HTMLElement).hidden = false
  ;($('error-state') as HTMLElement).hidden = true
  if (!isFallbackRetry) hideSortFallbackNote()

  setSummary()
  updateDistanceButtons()
  updateUrl()

  try {
    const data = await getTargetGenesData(state.genome, state.track, state.distance, {
      sort: state.sort || undefined,
      order: state.order,
      offset: state.offset,
      limit: PAGE_SIZE,
      q: state.query || undefined,
    })
    if (gen !== loadGeneration) return // a newer request (distance/sort/page change) already landed

    state.data = data
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = false

    renderHeader(data)
    renderRows(data)
    renderPagination(data)
    updateExperimentsToggleLabel(data)
    updateDownloadLink()
  } catch (err) {
    if (gen !== loadGeneration) return

    // The sort column carried over from a different distance (a different
    // precomputed file, which isn't guaranteed to have the same experiment
    // columns) can 400 as TargetGenesTsv::UnknownSortColumn. That's not
    // "this combination has no data" — it's "the old sort doesn't apply
    // here" — so fall back to the default sort and retry once instead of
    // showing the generic not-found message for a condition that isn't one.
    if (!isFallbackRetry && state.sort && isUnknownSortColumnError(err)) {
      const previousSort = state.sort
      console.warn(`Sort column "${previousSort}" not present at distance ${state.distance}; falling back to the default sort.`, err)
      state.sort = null
      state.order = 'desc'
      showSortFallbackNote(previousSort)
      void load(true)
      return
    }

    console.error(err)
    state.data = null
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = true
    ;($('download-tsv') as HTMLAnchorElement).hidden = true
    hideSortFallbackNote()
    const e = $('error-state') as HTMLElement
    e.textContent = 'Failed to load target genes. This antigen/genome/distance combination may not have precomputed data.'
    e.hidden = false
  }
}

function wireDistanceSwitch(): void {
  document.querySelectorAll<HTMLButtonElement>('#distance-switch button[data-distance]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const distance = btn.dataset.distance
      if (!distance || distance === state.distance) return
      state.distance = distance
      state.offset = 0
      void load()
    })
  })
}

function wirePagination(): void {
  $('page-prev').addEventListener('click', (e) => {
    e.preventDefault()
    if ($('page-prev').classList.contains('disabled')) return
    state.offset = Math.max(0, state.offset - PAGE_SIZE)
    void load()
  })
  $('page-next').addEventListener('click', (e) => {
    e.preventDefault()
    if ($('page-next').classList.contains('disabled')) return
    state.offset += PAGE_SIZE
    void load()
  })
}

// Debounced so each keystroke doesn't fire its own request against a
// potentially 13,459-row file; keeps the current sort and resets to page 1
// (offset 0), matching every other state change on this page (distance
// switch, sort click, pagination) that starts a fresh load from the top.
let queryDebounceTimer: ReturnType<typeof setTimeout> | null = null

function wireGeneSearch(): void {
  const input = $('gene-search') as HTMLInputElement
  input.addEventListener('input', () => {
    const value = input.value
    if (queryDebounceTimer !== null) clearTimeout(queryDebounceTimer)
    queryDebounceTimer = setTimeout(() => {
      queryDebounceTimer = null
      const trimmed = value.trim()
      if (trimmed === state.query) return
      state.query = trimmed
      state.offset = 0
      void load()
    }, QUERY_DEBOUNCE_MS)
  })
}

function wireExperimentsToggle(): void {
  const details = $('experiments-toggle') as HTMLDetailsElement
  const wrap = $('result-table-wrap')
  details.addEventListener('toggle', () => {
    wrap.classList.toggle('tg-experiments-expanded', details.open)
    if (state.data) updateExperimentsToggleLabel(state.data)
  })
}

function init(): void {
  const params = readQueryParams()
  if (!params) {
    ;($('loading-state') as HTMLElement).hidden = true
    const err = $('error-state') as HTMLElement
    err.textContent = 'Missing genome or track parameter in URL.'
    err.hidden = false
    return
  }

  state.genome = params.genome
  state.track = params.track
  state.distance = params.distance

  wireDistanceSwitch()
  wirePagination()
  wireExperimentsToggle()
  wireGeneSearch()

  void load()
}

// Guarded so the pure functions above (computeNextSort, computeAriaSort,
// isUnknownSortColumnError) can be imported and unit-tested under plain
// Node, which has no `document` — see target-genes-result.test.ts.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
