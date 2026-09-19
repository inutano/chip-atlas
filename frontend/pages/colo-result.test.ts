// frontend/pages/colo-result.test.ts
// Unit tests for the pure logic behind the Colocalization result page: the
// sort-state transitions shared in idiom with target-genes-result.ts, the
// row-sorting comparator, and the peak-intensity concordance value -> color
// mapping verified live against hg38/colo/STAT3.Blood.tsv + the paired
// .html (see colo-result.ts's CONCORDANCE_COLORS comment).
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { averageToRgb, computeAriaSort, computeNextSort, concordanceColor, isSelfComparison, sortRows } from './colo-result'

// ===== computeNextSort / computeAriaSort — identical contract to
// target-genes-result.ts's (see that file's tests for the fuller
// rationale); duplicated here because colo-result.ts duplicates the
// implementation rather than importing it (see that file's header comment
// for why: each frontend/pages/*.ts is its own esbuild entry point). =====

test('computeNextSort: a fresh column sorts descending first', () => {
  const next = computeNextSort({ sort: null, order: 'desc' }, 'Stat3|Average')
  assert.deepEqual(next, { sort: 'Stat3|Average', order: 'desc' })
})

test('computeNextSort: activating the already-sorted column flips desc -> asc -> desc', () => {
  let s = computeNextSort({ sort: null, order: 'desc' }, 'STRING')
  assert.deepEqual(s, { sort: 'STRING', order: 'desc' })
  s = computeNextSort(s, 'STRING')
  assert.deepEqual(s, { sort: 'STRING', order: 'asc' })
  s = computeNextSort(s, 'STRING')
  assert.deepEqual(s, { sort: 'STRING', order: 'desc' })
})

test('computeNextSort: activating a different column switches to it, descending', () => {
  const next = computeNextSort({ sort: 'STRING', order: 'asc' }, 'SRX150636|GM12878')
  assert.deepEqual(next, { sort: 'SRX150636|GM12878', order: 'desc' })
})

test('computeAriaSort: the active column reports its current direction', () => {
  assert.equal(computeAriaSort({ sort: 'STRING', order: 'desc' }, 'STRING'), 'descending')
  assert.equal(computeAriaSort({ sort: 'STRING', order: 'asc' }, 'STRING'), 'ascending')
})

test('computeAriaSort: every other column reports none', () => {
  assert.equal(computeAriaSort({ sort: 'STRING', order: 'desc' }, 'Stat3|Average'), 'none')
  assert.equal(computeAriaSort({ sort: null, order: 'desc' }, 'STRING'), 'none')
})

// ===== sortRows — the client-side re-sort that replaces a server round
// trip (the whole result is already in memory, see colo-result.ts's header
// comment) =====

test('sortRows: sorts numeric columns descending', () => {
  const rows: Array<Array<string | number>> = [
    ['SRX1', 'CellA', 'Stat3', 3],
    ['SRX2', 'CellB', 'Stat3', 9],
    ['SRX3', 'CellC', 'Stat3', 5],
  ]
  const sorted = sortRows(rows, 3, 'desc')
  assert.deepEqual(sorted.map((r) => r[0]), ['SRX2', 'SRX3', 'SRX1'])
})

test('sortRows: ascending reverses the order', () => {
  const rows: Array<Array<string | number>> = [
    ['SRX1', 'CellA', 'Stat3', 3],
    ['SRX2', 'CellB', 'Stat3', 9],
    ['SRX3', 'CellC', 'Stat3', 5],
  ]
  const sorted = sortRows(rows, 3, 'asc')
  assert.deepEqual(sorted.map((r) => r[0]), ['SRX1', 'SRX3', 'SRX2'])
})

test('sortRows: sorts a string column (e.g. Experiment or Cell type) lexicographically', () => {
  const rows: Array<Array<string | number>> = [
    ['SRX3', 'CellC', 'Stat3', 1],
    ['SRX1', 'CellA', 'Stat3', 1],
    ['SRX2', 'CellB', 'Stat3', 1],
  ]
  const sorted = sortRows(rows, 1, 'asc')
  assert.deepEqual(sorted.map((r) => r[1]), ['CellA', 'CellB', 'CellC'])
})

test('sortRows: does not mutate the input array', () => {
  const rows: Array<Array<string | number>> = [
    ['SRX1', 'CellA', 'Stat3', 3],
    ['SRX2', 'CellB', 'Stat3', 9],
  ]
  const original = rows.map((r) => r.slice())
  sortRows(rows, 3, 'desc')
  assert.deepEqual(rows, original)
})

// ===== concordanceColor — the peak-intensity legend mapping, verified live
// against hg38/colo/STAT3.Blood.tsv + .html (see colo-result.ts's
// CONCORDANCE_COLORS comment for the exact rows this was cross-checked
// against). `isSelf` is always passed explicitly - concordanceColor never
// infers a self-comparison from the value alone, see below. =====

test('concordanceColor: 0 is N.D. (gray)', () => {
  assert.deepEqual(concordanceColor(0, false), { hex: '#808080', rgb: [128, 128, 128], label: 'N.D.' })
})

test('concordanceColor: 9 is H-H (red)', () => {
  assert.deepEqual(concordanceColor(9, false), { hex: '#ff0000', rgb: [255, 0, 0], label: 'H-H' })
})

test('concordanceColor: 4 is M-M (green)', () => {
  assert.deepEqual(concordanceColor(4, false), { hex: '#00ff38', rgb: [0, 255, 56], label: 'M-M' })
})

test('concordanceColor: 6 is H-M (yellow-green)', () => {
  assert.deepEqual(concordanceColor(6, false), { hex: '#aaff00', rgb: [170, 255, 0], label: 'H-M' })
})

test('concordanceColor: 1 is L-L (blue), 2 is M-L, 3 is H-L', () => {
  assert.equal(concordanceColor(1, false).label, 'L-L')
  assert.equal(concordanceColor(1, false).hex, '#0071ff')
  assert.equal(concordanceColor(2, false).label, 'M-L')
  assert.equal(concordanceColor(2, false).hex, '#00e2ff')
  assert.equal(concordanceColor(3, false).label, 'H-L')
  assert.equal(concordanceColor(3, false).hex, '#00ffaa')
})

test('concordanceColor: an unrepresentable value (5, 7, 8, or a stray float) falls back to "?" rather than throwing', () => {
  assert.equal(concordanceColor(5, false).label, '?')
  assert.equal(concordanceColor(7, false).label, '?')
  assert.equal(concordanceColor(-1, false).label, '?')
})

// ===== 10 = "Same": structurally verified, not inferred from the value =====
//
// The H/M/L product formula tops out at 9, so a raw 10 can't arise as a
// real score today - but concordanceColor does not trust that inference on
// its own. It only renders "Same" when the caller has independently
// confirmed (via isSelfComparison, checked against the row's own
// Experiment id and this column's header) that this cell really is an
// experiment compared against itself. A 10 that isn't backed by that
// structural check - which should be unreachable given the formula, but
// costs nothing to guard - takes the same gray "?" fallback as any other
// unrepresentable value, never a confident, unverified "Same" in black.

test('concordanceColor: 10 with isSelf=true renders Same (black)', () => {
  assert.deepEqual(concordanceColor(10, true), { hex: '#000000', rgb: [0, 0, 0], label: 'Same' })
})

test('concordanceColor: 10 with isSelf=false falls back to "?", not Same', () => {
  const result = concordanceColor(10, false)
  assert.equal(result.label, '?')
  assert.notEqual(result.label, 'Same')
  assert.deepEqual(result, { hex: '#808080', rgb: [128, 128, 128], label: '?' })
})

// ===== averageToRgb — the Average column's color, mapped onto the same
// 0-1000 ramp as STRING (scoreToRgb, already exercised above via
// stringCell/concordanceColor's shared machinery) scaled by 1000/9. Pins
// the five worked examples from task F1's brief, cross-checked live
// against production's own hg38/colo/STAT3.Blood.html (1,000/1,000 rows,
// zero channel error) - this only asserts the scale factor's effect, since
// scoreToRgb's own ramp shape already has coverage elsewhere (see this
// file's header comment: colo-result.ts and target-genes-result.ts keep
// byte-identical scoreToRgb implementations on purpose). =====

function toHex([r, g, b]: [number, number, number]): string {
  return `#${[r, g, b].map((x) => x.toString(16).padStart(2, '0')).join('')}`
}

test('averageToRgb: average 3.866667 -> 429.6 on the ramp -> #00ff47', () => {
  assert.equal(toHex(averageToRgb(3.866667)), '#00ff47')
})

test('averageToRgb: average 3.000000 -> 333.3 on the ramp -> #00ffaa', () => {
  assert.equal(toHex(averageToRgb(3)), '#00ffaa')
})

test('averageToRgb: average 2.250000 -> 250.0 on the ramp -> exactly cyan #00ffff', () => {
  assert.equal(toHex(averageToRgb(2.25)), '#00ffff')
})

test('averageToRgb: average 2.125000 -> 236.1 on the ramp -> #00f0ff', () => {
  assert.equal(toHex(averageToRgb(2.125)), '#00f0ff')
})

test('averageToRgb: average 0 -> gray #808080 (no data), same as STRING\'s own 0', () => {
  assert.equal(toHex(averageToRgb(0)), '#808080')
})

// ===== isSelfComparison — the structural check itself =====
//
// Verified live that a row's Experiment id (column 1) and the id encoded
// in that same experiment's own reference-experiment column header
// (<SRX>|<CellType>) are spelled identically - checked against both
// SRX347427 (SU-DHL-4) and SRX347429 (U-2932) in hg38/colo/STAT3.Blood.tsv
// - so exact string equality is sufficient; no normalization/fuzzy match
// is implemented (see colo-result.ts's isSelfComparison comment).

test('isSelfComparison: true when the row Experiment id matches the column header\'s id', () => {
  assert.equal(isSelfComparison('SRX347427', 'SRX347427|SU-DHL-4'), true)
})

test('isSelfComparison: false when the row is a different experiment than the column', () => {
  assert.equal(isSelfComparison('SRX347427', 'SRX150636|GM12878'), false)
})

test('isSelfComparison: false for a column header with no matching id anywhere in it', () => {
  assert.equal(isSelfComparison('SRX347427', 'SRX999999|SomeOtherCell'), false)
})

test('isSelfComparison: falls back to comparing the whole header when it has no "|" separator', () => {
  assert.equal(isSelfComparison('SRX1', 'SRX1'), true)
  assert.equal(isSelfComparison('SRX1', 'SRX2'), false)
})
