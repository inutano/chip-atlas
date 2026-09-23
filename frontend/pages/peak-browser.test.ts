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
import { peakBrowserFacetFilterOptions, resolveSubclassExclusion, qvalListBoxSize } from './peak-browser'

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

// ===== qvalListBoxSize — production's fixed size=5, except the degenerate
// single-"NA"-option case (Bisulfite-Seq/Annotation tracks) =====
// Fix-round-1 regression: an earlier version of this formula
// (Math.max(2, Math.min(5, optionCount))) also shrank the box for the
// *normal* four-option case (every real track class) to 4, contradicting
// production's own fixed size=5 there. Each case below gets its own
// assertion specifically so that regression cannot come back silently.

test('qvalListBoxSize: 0 options (nothing loaded yet) -> 2', () => {
  assert.equal(qvalListBoxSize(0), 2)
})

test('qvalListBoxSize: 1 option (Bisulfite-Seq/Annotation tracks\' fixed "NA") -> 2, not 5 blank rows', () => {
  assert.equal(qvalListBoxSize(1), 2)
})

test('qvalListBoxSize: 4 options (the normal case: Histone, RNA polymerase, TFs and others, ...) -> production\'s 5', () => {
  assert.equal(qvalListBoxSize(4), 5)
})

test('qvalListBoxSize: 8 options (hypothetical larger list) -> still 5, same fixed size as production', () => {
  assert.equal(qvalListBoxSize(8), 5)
})
