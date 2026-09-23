// frontend/components/autocomplete.test.ts
// Unit tests for exactMatch, the pure helper behind Autocomplete's paired
// ListBox sync (COLO-04, TG-09): production's typeahead:select/keyup handler
// wrote whatever the input held straight into the <select> whenever it named
// an option exactly (old-app/public/js/pj/colo.js:151-159,
// target_genes.js:152-157). exactMatch is the case-insensitive, trimmed
// equivalent of that `$.inArray(input, options) > -1` check.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { exactMatch, resolvePairedSelection } from './autocomplete'

const ITEMS = ['AATF', 'STAT3']

test('exactMatch: an exact match (case-insensitive, trimmed) returns the item as stored', () => {
  assert.equal(exactMatch(ITEMS, 'stat3 '), 'STAT3')
})

test('exactMatch: no item matches returns null', () => {
  assert.equal(exactMatch(ITEMS, 'CTCF'), null)
})

test('exactMatch: empty text returns null', () => {
  assert.equal(exactMatch(ITEMS, ''), null)
})

test('exactMatch: whitespace-only text returns null', () => {
  assert.equal(exactMatch(ITEMS, '   '), null)
})

test('exactMatch: a substring match is not an exact match', () => {
  assert.equal(exactMatch(ITEMS, 'AAT'), null)
})

// resolvePairedSelection: the paired ListBox's selection after a keystroke
// or a fresh item list, as one decision (2026-09-24 review, finding 3) —
// exact match, then a still-present current selection, then the first item.
// See autocomplete.ts's comment above the function for the bug this
// replaces: a partial query's auto-selected first row never used to reach
// the page's own state.

test('resolvePairedSelection: an exact match wins even over a still-valid current selection', () => {
  assert.deepEqual(
    resolvePairedSelection(['STAG1', 'STAT3'], 'stat3', 'STAG1'),
    { selected: 'STAT3', changed: true },
  )
})

test('resolvePairedSelection: keeps the current selection when it is still among the filtered items', () => {
  // STAG1 is not alphabetically first (STAG2 is), so this only passes if
  // "keep current" is actually checked before "default to first".
  assert.deepEqual(
    resolvePairedSelection(['STAG2', 'STAG1'], 'stag', 'STAG1'),
    { selected: 'STAG1', changed: false },
  )
})

test('resolvePairedSelection: falls back to the first filtered item when current is no longer present', () => {
  assert.deepEqual(
    resolvePairedSelection(['STAG1', 'STAT3'], 'sta', 'AATF'),
    { selected: 'STAG1', changed: true },
  )
})

test('resolvePairedSelection: falls back to the first item when there is no current selection yet', () => {
  assert.deepEqual(
    resolvePairedSelection(['AATF', 'STAT3'], '', null),
    { selected: 'AATF', changed: true },
  )
})

test('resolvePairedSelection: an empty item list resolves to no selection', () => {
  assert.deepEqual(
    resolvePairedSelection([], '', null),
    { selected: null, changed: false },
  )
})

test('resolvePairedSelection: an empty item list reports a change when something was previously selected', () => {
  assert.deepEqual(
    resolvePairedSelection([], 'zz', 'AATF'),
    { selected: null, changed: true },
  )
})

// force (2026-09-24 fix round 2): Autocomplete.setItems' contract for a
// wholesale item replacement. "Others" is a valid partner of more than one
// antigen in the real /api/colo_index data (AATF's only partner, and one of
// STAG1's/STAT3's ten) -- without `force`, setItems wrongly kept "Others"
// selected for a brand new antigen's partner list just because the string
// happened to still be present, instead of resetting like a fresh list
// should. Verified live: picking STAT3 left the secondary panel on "Others"
// (carried over from the initial antigen, AATF) rather than resetting to
// STAT3's own first partner, Blood.

test('resolvePairedSelection: force=true skips "keep current" and always defaults to the first item', () => {
  assert.deepEqual(
    resolvePairedSelection(['Blood', 'Bone', 'Others'], '', 'Others', true),
    { selected: 'Blood', changed: true },
  )
})

test('resolvePairedSelection: force=true still lets an exact query match win (setItems never passes a query, but the priority still holds)', () => {
  assert.deepEqual(
    resolvePairedSelection(['Blood', 'Bone'], 'bone', 'Blood', true),
    { selected: 'Bone', changed: true },
  )
})

test('resolvePairedSelection: force defaults to false, leaving open()\'s existing "keep current" behaviour unchanged', () => {
  assert.deepEqual(
    resolvePairedSelection(['Blood', 'Bone', 'Others'], '', 'Others'),
    { selected: 'Others', changed: false },
  )
})
