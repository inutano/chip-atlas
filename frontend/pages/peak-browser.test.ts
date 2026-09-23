// frontend/pages/peak-browser.test.ts
// Unit test for Task D2's Peak Browser side of the Enrichment-Analysis-only
// "Annotation tracks" exclusion: Peak Browser must keep every track class
// FacetFilter is handed, since annotation tracks are a legitimate track type
// there. peakBrowserFacetFilterOptions is the exact function the
// genome-change handler in init() calls to build FacetFilter.init's options
// (`FacetFilter.init(facet, detail.genome, peakBrowserFacetFilterOptions(mount))`),
// so this test fails if a future edit accidentally adds an exclusion here —
// not just if a standalone helper regresses. See
// frontend/pages/enrichment-analysis.test.ts for the mirror-image assertion
// that Enrichment Analysis *does* exclude Annotation tracks, and
// frontend/components/facet-filter.test.ts for the underlying
// excludeTrackClasses filter both pages share.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { peakBrowserFacetFilterOptions, resolveSubclassExclusion } from './peak-browser'

test('peakBrowserFacetFilterOptions: passes no track-class exclusion (keeps Annotation tracks)', () => {
  const mount = {} as Record<
    'track_class' | 'track_subclass' | 'cell_type_class' | 'cell_type_subclass' | 'qval',
    HTMLElement
  >
  const opts = peakBrowserFacetFilterOptions(mount)
  assert.equal('excludeTrackClassIds' in opts, false)
  assert.equal(opts.render, 'listbox')
  assert.equal(opts.mount, mount)
})

// ===== resolveSubclassExclusion — PB-16 antigen/cell-type mutual exclusion =====
// Production (peak_browser.js:318-360) never lets both the "Track type
// (optional)" (track_subclass, aka antigen) and "Cell type (optional)"
// (cell_type_subclass) panels hold a real (non-"-") selection at once: the
// side the user did NOT just change gets reset back to "-" (All). See
// task-2-report.md and facet-filter.ts's trackSubclassItemsFor/dispatchFacetChange
// for why this is keyed off which select the user actually touched, not just
// "are both non-'-' right now".

test('resolveSubclassExclusion: both set, track_subclass just changed -> resets cell_type_subclass', () => {
  assert.deepEqual(
    resolveSubclassExclusion('track_subclass', 'CENPA', 'K-562'),
    { resetFacet: 'cell_type_subclass' },
  )
})

test('resolveSubclassExclusion: both set, cell_type_subclass just changed -> resets track_subclass', () => {
  assert.deepEqual(
    resolveSubclassExclusion('cell_type_subclass', 'CENPA', 'K-562'),
    { resetFacet: 'track_subclass' },
  )
})

test('resolveSubclassExclusion: track_subclass is "-" (All) -> no reset needed', () => {
  assert.deepEqual(
    resolveSubclassExclusion('cell_type_subclass', '-', 'K-562'),
    { resetFacet: null },
  )
})

test('resolveSubclassExclusion: cell_type_subclass is "-" (All) -> no reset needed', () => {
  assert.deepEqual(
    resolveSubclassExclusion('track_subclass', 'CENPA', '-'),
    { resetFacet: null },
  )
})

test('resolveSubclassExclusion: both "-" (All) -> no reset needed', () => {
  assert.deepEqual(
    resolveSubclassExclusion('track_subclass', '-', '-'),
    { resetFacet: null },
  )
})
