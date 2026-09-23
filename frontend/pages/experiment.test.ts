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
import { showAnalyzeMenu } from './experiment'

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
