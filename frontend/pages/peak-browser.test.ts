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
import { peakBrowserFacetFilterOptions } from './peak-browser'

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
