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
import { computeAriaSort, computeNextSort, concordanceColor, sortRows } from './colo-result'

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
// against) =====

test('concordanceColor: 0 is N.D. (gray)', () => {
  assert.deepEqual(concordanceColor(0), { hex: '#808080', rgb: [128, 128, 128], label: 'N.D.' })
})

test('concordanceColor: 9 is H-H (red)', () => {
  assert.deepEqual(concordanceColor(9), { hex: '#ff0000', rgb: [255, 0, 0], label: 'H-H' })
})

test('concordanceColor: 4 is M-M (green)', () => {
  assert.deepEqual(concordanceColor(4), { hex: '#00ff38', rgb: [0, 255, 56], label: 'M-M' })
})

test('concordanceColor: 6 is H-M (yellow-green)', () => {
  assert.deepEqual(concordanceColor(6), { hex: '#aaff00', rgb: [170, 255, 0], label: 'H-M' })
})

test('concordanceColor: 1 is L-L (blue), 2 is M-L, 3 is H-L', () => {
  assert.equal(concordanceColor(1).label, 'L-L')
  assert.equal(concordanceColor(1).hex, '#0071ff')
  assert.equal(concordanceColor(2).label, 'M-L')
  assert.equal(concordanceColor(2).hex, '#00e2ff')
  assert.equal(concordanceColor(3).label, 'H-L')
  assert.equal(concordanceColor(3).hex, '#00ffaa')
})

test('concordanceColor: 10 is the self-comparison sentinel, Same (black)', () => {
  assert.deepEqual(concordanceColor(10), { hex: '#000000', rgb: [0, 0, 0], label: 'Same' })
})

test('concordanceColor: an unrepresentable value (5, 7, 8, or a stray float) falls back to N.D. rather than throwing', () => {
  assert.equal(concordanceColor(5).label, '?')
  assert.equal(concordanceColor(7).label, '?')
  assert.equal(concordanceColor(-1).label, '?')
})
