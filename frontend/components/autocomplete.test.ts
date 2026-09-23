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
import { exactMatch } from './autocomplete'

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
