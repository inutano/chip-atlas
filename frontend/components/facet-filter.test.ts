// frontend/components/facet-filter.test.ts
// Unit tests for the pure logic behind FacetFilter's track-class exclusion
// (Task D2): Enrichment Analysis passes `excludeTrackClassIds: ['Annotation
// tracks']` into FacetFilter.init so its experiment-type list matches
// production's generateExperimentTypeOptions(), which explicitly drops
// "Annotation tracks" (`if (label != "Annotation tracks")`). Peak Browser
// does not pass this option, so it keeps every track class FacetFilter is
// handed — annotation tracks are a legitimate track type there. See
// enrichment-analysis.ts and peak-browser.ts for the two call sites.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { excludeTrackClasses, qvalOptionsFor, trackSubclassItemsFor, NA_ONLY_TRACK_CLASSES } from './facet-filter'
import type { ClassificationItem } from '../api/client'

const items: ClassificationItem[] = [
  { id: 'Histone', label: 'ChIP: Histone', count: 10 },
  { id: 'ATAC-Seq', label: 'ATAC-Seq', count: 5 },
  { id: 'Annotation tracks', label: 'Annotation tracks', count: 1 },
]

test('excludeTrackClasses: with no exclusion list, returns every item unchanged (Peak Browser)', () => {
  assert.deepEqual(excludeTrackClasses(items, []), items)
})

test('excludeTrackClasses: drops only the excluded id, keeping everything else (Enrichment Analysis)', () => {
  const result = excludeTrackClasses(items, ['Annotation tracks'])
  assert.deepEqual(result.map((it) => it.id), ['Histone', 'ATAC-Seq'])
})

test('excludeTrackClasses: an exclusion id absent from the items is a no-op', () => {
  const result = excludeTrackClasses(items, ['CUT&Tag'])
  assert.deepEqual(result, items)
})

// ===== qvalOptionsFor (PB-18, PB-19) =====
//
// Production (old-app/public/js/pj/peak_browser.js:245-262) sends a fixed
// "NA" option instead of the four /qvalue_range codes for these two track
// classes: 'bs' for Bisulfite-Seq (the significance threshold does not apply
// to methylation calls), 'anno' for Annotation tracks. Every other track
// class gets the real codes, labelled the same way production always has
// (-10*Log10(Q), e.g. "05" -> "50").

test('qvalOptionsFor: Bisulfite-Seq is a fixed single "NA" row with value "bs", ignoring apiValues', () => {
  assert.deepEqual(qvalOptionsFor('Bisulfite-Seq', ['05', '10', '20', '50']), [{ id: 'bs', label: 'NA' }])
  assert.deepEqual(qvalOptionsFor('Bisulfite-Seq', []), [{ id: 'bs', label: 'NA' }])
})

test('qvalOptionsFor: Annotation tracks is a fixed single "NA" row with value "anno", ignoring apiValues', () => {
  assert.deepEqual(qvalOptionsFor('Annotation tracks', ['05', '10', '20', '50']), [{ id: 'anno', label: 'NA' }])
  assert.deepEqual(qvalOptionsFor('Annotation tracks', []), [{ id: 'anno', label: 'NA' }])
})

test('qvalOptionsFor: any other track class maps the real /api/qval_range codes to production\'s -10*Log10(Q) labels', () => {
  assert.deepEqual(qvalOptionsFor('Histone', ['05', '10', '20', '50']), [
    { id: '05', label: '50' },
    { id: '10', label: '100' },
    { id: '20', label: '200' },
    { id: '50', label: '500' },
  ])
})

test('qvalOptionsFor: an empty apiValues list for a non-NA track class is an empty list, not an error', () => {
  assert.deepEqual(qvalOptionsFor('Histone', []), [])
})

// ===== trackSubclassItemsFor (PB-14, PB-19) =====
//
// Production (peak_browser.js:98-109) never calls /data/chip_antigen for
// Input control / ATAC-Seq / DNase-seq / Bisulfite-Seq - it hardcodes a
// single "NA" row (value "-"). For Annotation tracks (peak_browser.js:127-138)
// it does call the API but drops the "All" (id "-") entry so only real
// annotations are offered, leaving the first one selected (the existing
// ListBox/DropdownControl "preserve selection, else first row" logic already
// does that once "-" is out of the list). Every other track class is passed
// through unchanged.

test('trackSubclassItemsFor: Input control is a fixed single "NA" row, ignoring apiItems', () => {
  assert.deepEqual(trackSubclassItemsFor('Input control', items), [{ id: '-', label: 'NA', count: null }])
})

test('trackSubclassItemsFor: ATAC-Seq is a fixed single "NA" row, ignoring apiItems', () => {
  assert.deepEqual(trackSubclassItemsFor('ATAC-Seq', items), [{ id: '-', label: 'NA', count: null }])
})

test('trackSubclassItemsFor: DNase-seq (exact API casing) is a fixed single "NA" row, ignoring apiItems', () => {
  assert.deepEqual(trackSubclassItemsFor('DNase-seq', items), [{ id: '-', label: 'NA', count: null }])
})

test('trackSubclassItemsFor: DNase-Seq (production/display casing) does NOT match - only the API\'s own casing does', () => {
  // Guards against silently reintroducing this regression by "fixing" the
  // casing later: the real API id is lower-case "seq" (checked via
  // `curl 'http://localhost:9292/api/track_classes?genome=hg38'`), so a
  // title-case lookup must fall through to the "everything else" branch.
  assert.deepEqual(trackSubclassItemsFor('DNase-Seq', items), items)
})

test('trackSubclassItemsFor: Bisulfite-Seq is a fixed single "NA" row, ignoring apiItems', () => {
  assert.deepEqual(trackSubclassItemsFor('Bisulfite-Seq', items), [{ id: '-', label: 'NA', count: null }])
})

test('trackSubclassItemsFor: Annotation tracks drops the "All" ("-") entry and keeps the rest in order', () => {
  const apiItems: ClassificationItem[] = [
    { id: '-', label: 'All', count: null },
    { id: 'CAGE (fanta.bio): Enhancer', label: 'CAGE (fanta.bio): Enhancer', count: 1 },
    { id: 'CpG Islands', label: 'CpG Islands', count: 1 },
  ]
  assert.deepEqual(trackSubclassItemsFor('Annotation tracks', apiItems), [
    { id: 'CAGE (fanta.bio): Enhancer', label: 'CAGE (fanta.bio): Enhancer', count: 1 },
    { id: 'CpG Islands', label: 'CpG Islands', count: 1 },
  ])
})

test('trackSubclassItemsFor: any other track class (e.g. Histone) passes apiItems through unchanged, "All" included', () => {
  const apiItems: ClassificationItem[] = [
    { id: '-', label: 'All', count: null },
    { id: 'H3K4me3', label: 'H3K4me3', count: 5678 },
  ]
  assert.deepEqual(trackSubclassItemsFor('Histone', apiItems), apiItems)
})

test('NA_ONLY_TRACK_CLASSES: exactly the four classes, using the API\'s own ids/casing', () => {
  assert.deepEqual(
    [...NA_ONLY_TRACK_CLASSES].sort(),
    ['ATAC-Seq', 'Bisulfite-Seq', 'DNase-seq', 'Input control'].sort(),
  )
})
