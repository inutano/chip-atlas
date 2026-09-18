// frontend/pages/colo-result.ts
// Fetches /api/colo once and renders ChIP-Atlas's Colocalization result as
// a partner x reference-experiment peak-intensity concordance matrix,
// matching production's layout (verified live against
// hg38/colo/STAT3.Blood.html and its paired .tsv - see task B5's brief)
// rather than the Rank/Score/Shared-Bins ranked list this file used to
// render.
//
// Unlike Target Genes (frontend/pages/target-genes-result.ts), the whole
// result is small enough (263 KB / ~3,862 rows for STAT3/Blood) to fetch
// and hold in memory in one response: there is no offset/limit paging on
// /api/colo and no per-click network round trip for sorting - every header
// click re-sorts the array already in memory and re-renders. This module
// duplicates a few small pieces of target-genes-result.ts (the sortable
// header helper, the score-cell color math) rather than importing them,
// because esbuild.config.mjs bundles every frontend/pages/*.ts file as its
// own independent entry point - importing across pages would pull that
// other page's whole module (including its own DOMContentLoaded listener)
// into this one's bundle for no benefit.

import { getColoData, type ColoResult } from '../api/client'

const AVERAGE_SUFFIX = '|Average'
const STRING_COLUMN = 'STRING'
const LEADING_TEXT_COLUMNS = 3 // Experiment, Cell_subclass, Protein

interface Params {
  genome: string
  track: string
  cell_type: string
}

interface State {
  genome: string
  track: string
  cell_type: string
  sort: string | null    // exact column header to sort by; null = default (the Average column)
  order: 'asc' | 'desc'
  data: ColoResult | null
}

const state: State = {
  genome: '', track: '', cell_type: '', sort: null, order: 'desc', data: null,
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
  const cell_type = p.get('cell_type')
  if (!genome || !track || !cell_type) return null
  return { genome, track, cell_type }
}

// ===== Column bookkeeping =====

function averageColumnIndex(columns: string[]): number {
  const idx = columns.findIndex((c) => c.endsWith(AVERAGE_SUFFIX))
  return idx === -1 ? LEADING_TEXT_COLUMNS : idx
}

function stringColumnIndex(columns: string[]): number {
  const idx = columns.indexOf(STRING_COLUMN)
  return idx === -1 ? columns.length - 1 : idx
}

// Splits a reference-experiment column header ("SRX150636|GM12878") into
// its experiment id and cell type, the same way target-genes-result.ts
// does for its experiment columns. Falls back to treating the whole header
// as the id if it doesn't contain the separator.
function splitExperimentHeader(header: string): { experimentId: string; cellType: string } {
  const sep = header.indexOf('|')
  if (sep === -1) return { experimentId: header, cellType: '' }
  return { experimentId: header.slice(0, sep), cellType: header.slice(sep + 1) }
}

// Is this cell a reference experiment compared against itself? Checked
// structurally - row's own Experiment id (column 1 of every row) against
// the id encoded in this column's own header - rather than inferred from
// the raw score alone (see concordanceColor's comment for why that
// distinction matters). Exact string equality only: verified live that
// both sides are the same raw SRX accession spelling (e.g. row Experiment
// "SRX347427" against column header "SRX347427|SU-DHL-4" - confirmed
// against hg38/colo/STAT3.Blood.tsv for both SRX347427's and SRX347429's
// self-columns), so a fuzzy/normalized comparison isn't needed and isn't
// attempted - if a future TSV ever spells the same id two different ways
// across columns 1 and 5..n-1, this deliberately stops matching rather
// than guessing.
export function isSelfComparison(rowExperimentId: string, columnHeader: string): boolean {
  const { experimentId } = splitExperimentHeader(columnHeader)
  return experimentId === rowExperimentId
}

// ===== Peak-intensity concordance -> color + label =====
//
// Production computes these scores as products of H/M/L "binding-level"
// weights (H=3, M=2, L=1) for the query's reference experiment and this
// row's partner experiment: the only values that can occur are therefore
// {1,2,3,4,6,9} (H-H=9, H-M=M-H=6, H-L=L-H=3, M-M=4, M-L=L-M=2, L-L=1). 0
// means no shared-bin data at all ("N.D."). Verified live against
// hg38/colo/STAT3.Blood.tsv + the paired .html: a raw value of 10 appears
// exactly and only at a row's own reference-experiment column (a row
// comparing an experiment against itself) and is always rendered
// black/"Same" there - 10 can never arise from the H/M/L product formula,
// so as a *value* it's an unambiguous self-comparison sentinel. Colors
// themselves are production's exact legend swatches (see
// views/colo_result.erb).
//
// The formula guarantees 10 never means anything else *today*, but that's
// still an inference about an undocumented upstream encoding, and the
// failure mode of trusting it blindly is bad: a future data-server change
// that reused 10 for something else would render confidently as "Same" in
// black, no error, no gray fallback - exactly the kind of wrong-but-
// confident output a biologist would take as ground truth. The data
// already carries a second, structural signal that doesn't depend on the
// formula holding forever: column 1 of every row is that row's own
// Experiment id, and every reference-experiment column header encodes the
// id it represents (see isSelfComparison). So "Same" is only ever applied
// when *both* line up - the value is 10 *and* the row's identity actually
// matches this column's - checked by the caller (concordanceCell) via
// `isSelf`, not decided here from the value alone. A 10 that doesn't match
// (which should be unreachable today, but costs nothing to guard) falls
// through to the same gray "?" fallback as 5, 7, 8, or any other
// unrepresentable value.
const CONCORDANCE_COLORS: Record<number, { rgb: [number, number, number]; label: string }> = {
  0: { rgb: [128, 128, 128], label: 'N.D.' },
  1: { rgb: [0, 113, 255], label: 'L-L' },
  2: { rgb: [0, 226, 255], label: 'M-L' },
  3: { rgb: [0, 255, 170], label: 'H-L' },
  4: { rgb: [0, 255, 56], label: 'M-M' },
  6: { rgb: [170, 255, 0], label: 'H-M' },
  9: { rgb: [255, 0, 0], label: 'H-H' },
}
const SAME_CONCORDANCE: { rgb: [number, number, number]; label: string } = { rgb: [0, 0, 0], label: 'Same' }
const UNKNOWN_CONCORDANCE: { rgb: [number, number, number]; label: string } = { rgb: [128, 128, 128], label: '?' }
const SELF_SENTINEL_VALUE = 10

// `isSelf` is the structural check from isSelfComparison - this function
// never infers self-comparison from `value` alone. A value of 10 only
// renders as "Same" when the caller has already confirmed the row's
// Experiment id matches this column's; otherwise (including every other
// unrepresentable value) it falls back to gray "?".
export function concordanceColor(
  value: number,
  isSelf: boolean
): { hex: string; rgb: [number, number, number]; label: string } {
  const rounded = Math.round(value)
  const entry = rounded === SELF_SENTINEL_VALUE
    ? (isSelf ? SAME_CONCORDANCE : UNKNOWN_CONCORDANCE)
    : (CONCORDANCE_COLORS[rounded] ?? UNKNOWN_CONCORDANCE)
  return { hex: rgbToHex(entry.rgb), rgb: entry.rgb, label: entry.label }
}

// ===== STRING score -> color =====
// Identical domain/scale to Target Genes' STRING legend (see
// target-genes-result.ts's scoreToRgb) and to production's own colo STRING
// legend (0=blue .. 1000=red, gray for no data) - duplicated here rather
// than imported, see this file's header comment for why.
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

// ===== Sort state transitions (pure - mirrors target-genes-result.ts's
// computeNextSort/computeAriaSort; duplicated rather than imported, see
// this file's header comment) =====

export interface SortState {
  sort: string | null
  order: 'asc' | 'desc'
}

export function computeNextSort(current: SortState, column: string): SortState {
  if (current.sort === column) {
    return { sort: column, order: current.order === 'desc' ? 'asc' : 'desc' }
  }
  return { sort: column, order: 'desc' }
}

export function computeAriaSort(current: SortState, column: string): 'ascending' | 'descending' | 'none' {
  if (current.sort !== column) return 'none'
  return current.order === 'desc' ? 'descending' : 'ascending'
}

// Sorts a *copy* of `rows` by the column at `colIndex`, comparing
// numerically when both values are numbers (every data column except the
// leading Experiment/Cell_subclass/Protein triplet) and lexicographically
// otherwise. Never mutates the input - callers always re-derive the
// displayed rows from the original state.data.rows plus state.sort/order
// on every render, so switching sort column or order can never compound
// onto a previous sort's order.
export function sortRows(
  rows: Array<Array<string | number>>,
  colIndex: number,
  order: 'asc' | 'desc'
): Array<Array<string | number>> {
  const copy = rows.slice()
  copy.sort((a, b) => {
    const av = a[colIndex]
    const bv = b[colIndex]
    const cmp = typeof av === 'number' && typeof bv === 'number'
      ? av - bv
      : String(av).localeCompare(String(bv))
    return order === 'desc' ? -cmp : cmp
  })
  return copy
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
  renderTable()
}

// Builds a sortable <th> containing a real <button>, identical idiom to
// target-genes-result.ts's makeSortableHeader (see that file's comment for
// why a <button> rather than a click-on-<th> handler is required for
// keyboard operability).
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

  const hint = document.createElement('span')
  hint.className = 'visually-hidden'
  hint.textContent = sortStateHint(sortColumn)
  btn.appendChild(hint)

  btn.addEventListener('click', () => handleSortClick(sortColumn))
  th.appendChild(btn)
  return th
}

function renderHeader(data: ColoResult): void {
  const row = $('result-thead-row')
  const avgIdx = averageColumnIndex(data.columns)
  const strIdx = stringColumnIndex(data.columns)

  const cells: HTMLTableCellElement[] = []

  data.columns.forEach((col, i) => {
    if (i === 0) {
      cells.push(makeSortableHeader('Experiment', col))
      return
    }
    if (i === 1) {
      cells.push(makeSortableHeader('Cell type', col))
      return
    }
    if (i === 2) {
      cells.push(makeSortableHeader('Protein', col))
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

    // A reference-experiment column, hidden until "Show reference-experiment
    // columns" is expanded (same collapse-by-default idiom as Target
    // Genes' experiment columns).
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

function concordanceCell(value: number, isSelf: boolean): HTMLTableCellElement {
  const td = document.createElement('td')
  td.className = 'tg-score-cell tg-exp-col'
  const { hex, rgb, label } = concordanceColor(value, isSelf)
  td.style.backgroundColor = hex
  td.style.color = readableTextColor(rgb)
  td.textContent = label
  td.title = `raw concordance score: ${formatScore(value)}`
  return td
}

function stringCell(value: number): HTMLTableCellElement {
  const td = document.createElement('td')
  td.className = 'tg-score-cell'
  const rgb = scoreToRgb(value)
  td.style.backgroundColor = rgbToHex(rgb)
  td.style.color = readableTextColor(rgb)
  td.textContent = formatScore(value)
  return td
}

function renderRows(data: ColoResult, rows: Array<Array<string | number>>): void {
  const avgIdx = averageColumnIndex(data.columns)
  const strIdx = stringColumnIndex(data.columns)

  const tbody = $('result-tbody')
  tbody.replaceChildren(...rows.map((row) => {
    const tr = document.createElement('tr')
    const rowExperimentId = String(row[0])

    row.forEach((value, i) => {
      if (i === 0) {
        const td = document.createElement('td')
        const link = document.createElement('a')
        link.href = `/view?id=${encodeURIComponent(String(value))}`
        link.textContent = String(value)
        td.appendChild(link)
        tr.appendChild(td)
        return
      }
      if (i === 1 || i === 2) {
        const td = document.createElement('td')
        td.textContent = String(value)
        tr.appendChild(td)
        return
      }

      const numeric = typeof value === 'number' ? value : Number(value)
      if (i === avgIdx) {
        const td = document.createElement('td')
        td.className = 'tg-score-cell'
        td.textContent = formatScore(numeric)
        tr.appendChild(td)
        return
      }
      if (i === strIdx) {
        tr.appendChild(stringCell(numeric))
        return
      }
      // A reference-experiment (concordance) column: whether this
      // particular cell is a self-comparison is checked structurally
      // against this column's own header, not inferred from `numeric`
      // alone (see concordanceColor's comment).
      tr.appendChild(concordanceCell(numeric, isSelfComparison(rowExperimentId, data.columns[i])))
    })

    return tr
  }))
}

// Recomputes the sorted row order from state.data + state.sort/order and
// re-renders the header and body. The only place either is rendered, so
// header sort indicators and row order can never drift apart.
function renderTable(): void {
  const data = state.data
  if (!data) return

  const avgIdx = averageColumnIndex(data.columns)
  const sortColumn = state.sort ?? data.columns[avgIdx]
  const colIndex = data.columns.indexOf(sortColumn)
  const rows = sortRows(data.rows, colIndex === -1 ? avgIdx : colIndex, state.order)

  renderHeader(data)
  renderRows(data, rows)

  $('row-count').textContent = data.total === 0
    ? 'No colocalization partners found'
    : `${rows.length.toLocaleString()} colocalization partners`
}

function updateExperimentsToggleLabel(data: ColoResult): void {
  // Every column except Experiment/Cell_subclass/Protein/Average/STRING is
  // a reference-experiment column.
  const experimentCount = data.columns.length - LEADING_TEXT_COLUMNS - 2
  const summary = $('experiments-toggle-summary')
  const details = $('experiments-toggle') as HTMLDetailsElement
  summary.textContent = details.open
    ? `Hide reference-experiment columns (${experimentCount.toLocaleString()})`
    : `Show reference-experiment columns (${experimentCount.toLocaleString()})`
}

function updateDownloadLinks(): void {
  const params = new URLSearchParams({ genome: state.genome, track: state.track, cell_type: state.cell_type })
  const tsv = $('download-tsv') as HTMLAnchorElement
  tsv.href = `/api/colo/download?${params.toString()}&format=tsv`
  tsv.hidden = false
  const gml = $('download-gml') as HTMLAnchorElement
  gml.href = `/api/colo/download?${params.toString()}&format=gml`
  gml.hidden = false
}

function setSummary(): void {
  $('result-summary').textContent = `${state.track} (${state.cell_type}) on ${state.genome}`
}

async function load(): Promise<void> {
  ;($('loading-state') as HTMLElement).hidden = false
  ;($('error-state') as HTMLElement).hidden = true

  setSummary()

  try {
    const data = await getColoData(state.genome, state.track, state.cell_type)
    state.data = data
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = false

    renderTable()
    updateExperimentsToggleLabel(data)
    updateDownloadLinks()
  } catch (err) {
    console.error(err)
    state.data = null
    ;($('loading-state') as HTMLElement).hidden = true
    ;($('result-wrap') as HTMLElement).hidden = true
    ;($('download-tsv') as HTMLAnchorElement).hidden = true
    ;($('download-gml') as HTMLAnchorElement).hidden = true
    const e = $('error-state') as HTMLElement
    e.textContent = 'Failed to load colocalization data. This antigen/genome/cell-type combination may not have precomputed data.'
    e.hidden = false
  }
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
    err.textContent = 'Missing genome, track, or cell_type parameter in URL.'
    err.hidden = false
    return
  }

  state.genome = params.genome
  state.track = params.track
  state.cell_type = params.cell_type

  wireExperimentsToggle()

  void load()
}

// Guarded so the pure functions above (concordanceColor, isSelfComparison,
// computeNextSort, computeAriaSort, sortRows) can be imported and
// unit-tested under plain Node, which has no `document` - see
// colo-result.test.ts.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
