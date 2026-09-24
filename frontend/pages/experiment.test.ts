// frontend/pages/experiment.test.ts
// Unit test for SV-27: production hides the whole Analyze button group for
// Bisulfite-Seq experiments (old-app's experiment.js:126-131), because
// neither Colocalization nor Target Genes has Bisulfite-Seq data. This page
// had regressed to always rendering the Analyze menu, linking to result
// pages that don't exist for that track class.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { showAnalyzeMenu, buildVisualizeMenu } from './experiment'
import type { ExperimentRecord } from '../api/client'

test('showAnalyzeMenu: false for Bisulfite-Seq (no Colo/Target Genes data exists for it)', () => {
  assert.equal(showAnalyzeMenu('Bisulfite-Seq'), false)
})

test('showAnalyzeMenu: true for every other track class', () => {
  const trackClasses = [
    'Histone', 'TFs and others', 'RNA polymerase', 'Input control',
    'ATAC-Seq', 'DNase-seq', 'CUT&Tag', 'CUT&RUN',
  ]
  for (const trackClass of trackClasses) {
    assert.equal(showAnalyzeMenu(trackClass), true, `expected Analyze menu to show for ${trackClass}`)
  }
})

// ===== buildVisualizeMenu — IGV genome as a JSON URL (owner feedback R1) =====
// The owner's report: IGV desktop has no bundled TAIR12 genome, so the
// Visualize menu's hand-rolled IGV links (a separate builder from
// LocationService#igv_browsing_url - see igv.test.ts for that shared
// helper) silently fail to resolve for it via a bare genome code
// (genome=TAIR12). buildVisualizeMenu calls document.createElement
// directly, like every DOM-building helper in this file, so - consistent
// with this suite's no-jsdom convention (see autocomplete.test.ts etc) -
// this is the minimal fake needed to capture each anchor's assigned href
// without a real DOM.
function hrefsFromVisualizeMenu(data: Parameters<typeof buildVisualizeMenu>[0]): string[] {
  const hrefs: string[] = []
  const fakeDocument = {
    createElement: (tag: string) => {
      const el: Record<string, unknown> = { appendChild: (c: unknown) => c, setAttribute: () => {} }
      if (tag === 'a') {
        Object.defineProperty(el, 'href', { set: (v: string) => hrefs.push(v) })
      }
      return el
    },
  }
  ;(globalThis as unknown as { document: unknown }).document = fakeDocument
  buildVisualizeMenu(data)
  return hrefs
}

function tair12Record(): ExperimentRecord {
  return {
    experiment_id: 'DRX066754',
    genome: 'TAIR12',
    track_class: 'Histone',
    track_subclass: 'Unclassified',
    cell_type_class: 'Unclassified',
    cell_type_subclass: 'Unclassified',
    title: '',
    attributes: '',
    read_info: '',
    cell_type_subclass_info: '',
  }
}

test('buildVisualizeMenu: TAIR12 hrefs use the genome JSON URL, not the bare code (owner-reported defect)', () => {
  const hrefs = hrefsFromVisualizeMenu({ expid: 'DRX066754', records: [tair12Record()] })
  assert.equal(hrefs.length, 4) // BigWig + 3 peak-call links (q < 1E-05/10/20)
  for (const href of hrefs) {
    assert.match(href, /genome=https:\/\/chip-atlas\.dbcls\.jp\/data\/genome\/TAIR12\/TAIR12\.json/)
  }
})
