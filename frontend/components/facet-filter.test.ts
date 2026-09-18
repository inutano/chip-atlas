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
import { excludeTrackClasses } from './facet-filter'
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
