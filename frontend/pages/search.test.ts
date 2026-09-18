// frontend/pages/search.test.ts
// Unit tests for the pure logic behind the Data Search page's D1 (Title /
// Attributes columns) change: the attributes display formatting.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { formatAttributes } from './search'

// ===== formatAttributes =====

test('formatAttributes: replaces __TAB__ separators with a readable divider', () => {
  const raw = 'sample_name=DRS000203__TAB__strain=C2C12__TAB__sample comment=source: C2C12 cells'
  assert.equal(
    formatAttributes(raw),
    'sample_name=DRS000203 · strain=C2C12 · sample comment=source: C2C12 cells'
  )
})

test('formatAttributes: a string with no __TAB__ passes through unchanged', () => {
  assert.equal(formatAttributes('cell type=myoblast cells'), 'cell type=myoblast cells')
})

test('formatAttributes: an empty string stays empty', () => {
  assert.equal(formatAttributes(''), '')
})
