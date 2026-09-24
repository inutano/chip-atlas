// frontend/pages/search.test.ts
// Unit tests for the pure logic behind the Data Search page's D1 (Title /
// Attributes columns), D3 (GEO link) and R9 (attribute hit window +
// highlighting) changes.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  formatAttributes, geoAccUrl,
  ATTRIBUTES_WINDOW_LENGTH, searchTerms, firstHitIndex, attributesWindow, highlightSegments,
} from './search'

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

// ===== R9: attribute hit window + highlighting =====
// A match inside the collapsed "attributes" text used to be invisible: the
// preview was always the first 100 characters, and expanding showed the
// whole text again below it (SCRATCH/investigation/search.md §2, §4.2).
// searchTerms/firstHitIndex/attributesWindow/highlightSegments replace that
// with a window centred on the first hit and inline <mark> highlighting.

test('ATTRIBUTES_WINDOW_LENGTH: the window is 100 characters', () => {
  assert.equal(ATTRIBUTES_WINDOW_LENGTH, 100)
})

// ===== searchTerms =====
// Mirrors ChipAtlas::ExperimentSearch.match_expression's tokenisation
// (lib/models/experiment_search.rb): whitespace-split, "quoted phrases"
// kept whole, FTS5 metacharacters stripped, empty terms dropped.

test('searchTerms: whitespace-splits, keeps a quoted phrase whole, and strips FTS metacharacters', () => {
  assert.deepEqual(searchTerms('K562 "chip antibody" (x)'), ['K562', 'chip antibody', 'x'])
})

test('searchTerms: an empty query has no terms', () => {
  assert.deepEqual(searchTerms(''), [])
})

test('searchTerms: metacharacter-only input drops to no terms', () => {
  assert.deepEqual(searchTerms('***'), [])
  assert.deepEqual(searchTerms('""'), [])
  assert.deepEqual(searchTerms('   '), [])
})

// ===== firstHitIndex =====

test('firstHitIndex: finds a case-insensitive occurrence', () => {
  assert.equal(firstHitIndex('Cell line: k562', ['K562']), 11)
})

test('firstHitIndex: -1 when no term occurs', () => {
  assert.equal(firstHitIndex('Cell line: k562', ['CTCF']), -1)
})

test('firstHitIndex: the earliest match wins among multiple terms', () => {
  assert.equal(firstHitIndex('foo bar baz', ['baz', 'bar']), 4)
})

// ===== attributesWindow =====

test('attributesWindow: a string no longer than the window is returned unchanged (no ellipsis)', () => {
  const short = 'source_name=CD4 T cells · strain=C57BL/6'
  assert.equal(attributesWindow(short, ['CD4']), short)
})

test('attributesWindow: a hit inside the first window starts at 0 with a trailing ellipsis only', () => {
  const text = 'a'.repeat(20) + 'NEEDLE' + 'b'.repeat(274)  // 300 chars total, hit at offset 20
  const result = attributesWindow(text, ['NEEDLE'])
  assert.equal(result, text.slice(0, 100) + '…')
  assert.ok(!result.startsWith('…'))
})

test('attributesWindow: a hit past the window is centred with a leading and trailing ellipsis', () => {
  const text = 'a'.repeat(300) + 'NEEDLE' + 'b'.repeat(194)  // 500 chars total, hit at offset 300
  const result = attributesWindow(text, ['NEEDLE'])
  assert.ok(result.startsWith('…'))
  assert.ok(result.endsWith('…'))
  const inner = result.slice(1, -1)
  assert.equal(inner.length, 100)
  assert.ok(inner.includes('NEEDLE'))
})

test('attributesWindow: a hit near the end clamps the window to the tail with no trailing ellipsis', () => {
  const text = 'a'.repeat(450) + 'NEEDLE' + 'b'.repeat(44)  // 500 chars total, hit at offset 450
  const result = attributesWindow(text, ['NEEDLE'])
  assert.equal(result, '…' + text.slice(400, 500))
  assert.ok(!result.endsWith('…'))
})

test('attributesWindow: no hit falls back to the head of the string, unchanged from before', () => {
  const text = 'a'.repeat(300)
  assert.equal(attributesWindow(text, ['NEEDLE']), text.slice(0, 100) + '…')
})

// ===== highlightSegments =====

test('highlightSegments: wraps a case-insensitive hit, keeping the surrounding text as plain segments', () => {
  assert.deepEqual(highlightSegments('a K562 b', ['k562']), [
    { text: 'a ', hit: false },
    { text: 'K562', hit: true },
    { text: ' b', hit: false },
  ])
})

test('highlightSegments: no terms returns the whole text as a single plain segment', () => {
  assert.deepEqual(highlightSegments('a K562 b', []), [{ text: 'a K562 b', hit: false }])
})

test('highlightSegments: prefers the longest matching term at a given position and never overlaps', () => {
  assert.deepEqual(highlightSegments('K562 cells', ['K5', 'K562']), [
    { text: 'K562', hit: true },
    { text: ' cells', hit: false },
  ])
})
