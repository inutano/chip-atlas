// frontend/pages/colo.test.ts
// Unit tests for the two pure functions behind the Colocalization picker's
// panels. Until the colocalization index landed (task B4) this page was gated
// off entirely, so none of this had ever run against real data.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { primaryItemsFor, secondaryItemsFor } from './colo'
import type { ColoIndexEntry } from '../api/client'

// Shaped like a real /api/colo_index response: antigen -> cell-type classes,
// and the reverse. STAT3 really does sit in Blood and Liver on hg38.
const ENTRY: ColoIndexEntry = {
  track: {
    STAT3: ['Blood', 'Liver'],
    CTCF: ['Blood', 'Breast', 'Lung'],
  },
  cell_type: {
    Blood: ['STAT3', 'CTCF'],
    Liver: ['STAT3'],
    Breast: ['CTCF'],
    Lung: ['CTCF'],
  },
}

// ===== primaryItemsFor =====

test('primaryItemsFor: antigen mode offers every antigen', () => {
  // Sorted (COLO-03): production's appendOptions always called
  // options.sort() before rendering, so alphabetical, not entry.track's
  // insertion order (STAT3 before CTCF).
  assert.deepEqual(primaryItemsFor(ENTRY, 'track'), ['CTCF', 'STAT3'])
})

test('primaryItemsFor: cell-type mode offers every cell-type class', () => {
  assert.deepEqual(primaryItemsFor(ENTRY, 'cell_type'), ['Blood', 'Breast', 'Liver', 'Lung'])
})

test('primaryItemsFor: empty for a genome with no index loaded yet', () => {
  assert.deepEqual(primaryItemsFor(undefined, 'track'), [])
})

// ===== secondaryItemsFor =====
//
// The panel narrows to the chosen primary's partners. Before anything is
// chosen it shows everything on offer, which is also what makes the split
// between the two functions matter: the primary panel's contents never
// depend on the selection, so re-deriving them on every pick would re-render
// its list box and throw the visible selection back to the first row.

test('secondaryItemsFor: narrows to the chosen antigen\'s cell types', () => {
  assert.deepEqual(secondaryItemsFor(ENTRY, 'track', 'STAT3'), ['Blood', 'Liver'])
  assert.deepEqual(secondaryItemsFor(ENTRY, 'track', 'CTCF'), ['Blood', 'Breast', 'Lung'])
})

test('secondaryItemsFor: narrows to the chosen cell type\'s antigens', () => {
  assert.deepEqual(secondaryItemsFor(ENTRY, 'cell_type', 'Blood'), ['STAT3', 'CTCF'])
  assert.deepEqual(secondaryItemsFor(ENTRY, 'cell_type', 'Liver'), ['STAT3'])
})

test('secondaryItemsFor: with nothing chosen, offers everything this genome has', () => {
  // Not an empty box: the panel should show the range on offer before the
  // user has narrowed it. Sorted (COLO-03), same as primaryItemsFor.
  assert.deepEqual(secondaryItemsFor(ENTRY, 'track', ''), ['Blood', 'Breast', 'Liver', 'Lung'])
  assert.deepEqual(secondaryItemsFor(ENTRY, 'cell_type', ''), ['CTCF', 'STAT3'])
})

test('secondaryItemsFor: a primary the index does not know falls back to everything', () => {
  // Reachable by switching genome while a selection is live: the name is
  // carried for an instant against an index that may not contain it. An
  // empty panel would read as "this antigen has no partners", which is a
  // different and wrong claim.
  assert.deepEqual(secondaryItemsFor(ENTRY, 'track', 'NOT_IN_INDEX'), ['Blood', 'Breast', 'Liver', 'Lung'])
})

test('secondaryItemsFor: empty for a genome with no index loaded yet', () => {
  assert.deepEqual(secondaryItemsFor(undefined, 'track', 'STAT3'), [])
})

test('secondaryItemsFor: the two directions are genuine inverses of each other', () => {
  for (const antigen of primaryItemsFor(ENTRY, 'track')) {
    for (const cell of secondaryItemsFor(ENTRY, 'track', antigen)) {
      assert.ok(
        secondaryItemsFor(ENTRY, 'cell_type', cell).includes(antigen),
        `${antigen} lists ${cell}, so ${cell} must list ${antigen}`,
      )
    }
  }
})

// ===== sorting (COLO-03) =====
//
// Object.keys() preserves insertion order, which for /api/colo_index is the
// data's first-seen order, not an alphabetical one (verified wrong for every
// genome's cell-type-class panel). Production's appendOptions always called
// options.sort() before rendering, so both list boxes came out alphabetical
// regardless of the index's key order. This fixture's key order (STAT3
// before AATF, Others before Blood) is deliberately not alphabetical, so a
// passing test here cannot be an accident of already-sorted input.

const UNSORTED_ENTRY: ColoIndexEntry = {
  track: { STAT3: ['Blood'], AATF: ['Others'] },
  cell_type: { Others: ['AATF'], Blood: ['STAT3'] },
}

test('primaryItemsFor: sorts with JavaScript\'s default .sort(), not insertion order', () => {
  assert.deepEqual(primaryItemsFor(UNSORTED_ENTRY, 'track'), ['AATF', 'STAT3'])
})

test('secondaryItemsFor: the "offers everything" fallback sorts too', () => {
  assert.deepEqual(secondaryItemsFor(UNSORTED_ENTRY, 'track', ''), ['Blood', 'Others'])
})
