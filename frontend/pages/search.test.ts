// frontend/pages/search.test.ts
// Unit tests for the pure logic behind the Data Search page's D1 (Title /
// Attributes columns) and D3 (GEO link) changes.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { formatAttributes, geoAccUrl } from './search'

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

// ===== geoAccUrl =====

test('geoAccUrl: builds the NCBI GEO accession URL for a real id', () => {
  assert.equal(
    geoAccUrl('GSE12345'),
    'https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE12345'
  )
})

test('geoAccUrl: returns null for the "no GEO record" placeholder', () => {
  assert.equal(geoAccUrl('-'), null)
})

test('geoAccUrl: returns null for an empty id', () => {
  assert.equal(geoAccUrl(''), null)
})

test('geoAccUrl: percent-encodes ids that need it', () => {
  assert.equal(
    geoAccUrl('GSE 123/x'),
    'https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE%20123%2Fx'
  )
})
