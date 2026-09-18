// frontend/pages/enrichment-analysis.test.ts
// Unit tests for the pure logic behind the Enrichment Analysis job-submission
// payload (Task C1, D7/D8/D10 in
// docs/superpowers/plans/2026-09-18-post-parity-fixes.md):
//
//  - qvalCodeToThreshold: the qval facet (shared with Peak Browser) exposes
//    the allPeaks_light.<genome>.{05,10,20,50}.bed.gz filename codes as its
//    option values. WABI's `threshold` field wants the *other* encoding
//    production displays for the same four choices (50/100/200/500). These
//    are two different encodings that happen to share the digits "50" for
//    opposite ends of the range (the file code for the loosest threshold is
//    the WABI value for the strictest one) — this is exactly the hazard
//    flagged in the task brief, and the reason every one of the four labels
//    gets its own assertion below rather than a single spot check.
//  - buildEnrichmentParams: the full WABI-field-name payload (D7's "no
//    translation layer" — the frontend emits WABI's own names directly).
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildEnrichmentParams, qvalCodeToThreshold, type EnrichmentFormState } from './enrichment-analysis'

// ===== qvalCodeToThreshold — the two-encodings hazard =====

test('qvalCodeToThreshold: "05" (loosest file code) -> "50" (strictest WABI threshold label)', () => {
  assert.equal(qvalCodeToThreshold('05'), '50')
})

test('qvalCodeToThreshold: "10" -> "100"', () => {
  assert.equal(qvalCodeToThreshold('10'), '100')
})

test('qvalCodeToThreshold: "20" -> "200"', () => {
  assert.equal(qvalCodeToThreshold('20'), '200')
})

test('qvalCodeToThreshold: "50" (strictest file code) -> "500" (loosest WABI threshold label)', () => {
  assert.equal(qvalCodeToThreshold('50'), '500')
})

// ===== buildEnrichmentParams — full WABI field-name payload =====

const baseForm: EnrichmentFormState = {
  aType: 'bed',
  bType: 'rnd',
  dataAText: 'chr1\t1\t100',
  dataBText: '',
  title: 'My project',
  dataATitle: 'Dataset A',
  dataBTitle: 'Dataset B',
  permTime: '1',
  distanceUp: '5000',
  distanceDown: '5000',
}

const baseCondition = {
  genome: 'hg38',
  track_class: 'Histone',
  cell_type_class: 'Blood',
  qval: '05',
}

test('buildEnrichmentParams: renames every field to WABI\'s own names (D7)', () => {
  const params = buildEnrichmentParams(baseCondition, baseForm)

  assert.equal(params.genome, 'hg38')
  assert.equal(params.antigenClass, 'Histone')
  assert.equal(params.cellClass, 'Blood')
  assert.equal(params.threshold, '50')
  assert.equal(params.typeA, 'bed')
  assert.equal(params.bedAFile, 'chr1\t1\t100')
  assert.equal(params.typeB, 'rnd')
  assert.equal(params.title, 'My project')
  assert.equal(params.descriptionA, 'Dataset A')
  assert.equal(params.descriptionB, 'Dataset B')
  assert.equal(params.distanceUp, '5000')
  assert.equal(params.distanceDown, '5000')

  // None of the old internal field names should leak onto the wire.
  for (const old of ['track_class', 'cell_type_class', 'qval', 'dataA_type', 'dataA', 'dataB_type', 'dataB', 'permutations', 'dataA_title', 'dataB_title']) {
    assert.equal(Object.prototype.hasOwnProperty.call(params, old), false, `stale field "${old}" leaked into the WABI payload`)
  }
})

test('buildEnrichmentParams: the submitted threshold matches production\'s label for each of the four choices', () => {
  const cases: Array<[string, string]> = [
    ['05', '50'],
    ['10', '100'],
    ['20', '200'],
    ['50', '500'],
  ]
  for (const [code, expectedThreshold] of cases) {
    const params = buildEnrichmentParams({ ...baseCondition, qval: code }, baseForm)
    assert.equal(params.threshold, expectedThreshold, `qval code "${code}" should submit threshold "${expectedThreshold}"`)
  }
})

test('buildEnrichmentParams: permTime is included only when dataset B is random permutation', () => {
  const rnd = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'rnd', permTime: '10' })
  assert.equal(rnd.permTime, '10')

  const bed = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'bed', dataBText: 'chr1\t1\t100' })
  assert.equal('permTime' in bed, false)
})

test('buildEnrichmentParams: bedBFile is included only when dataset B needs content (bed or userlist)', () => {
  const bed = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'bed', dataBText: 'chr2\t1\t100' })
  assert.equal(bed.bedBFile, 'chr2\t1\t100')

  const userlist = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'userlist', dataBText: 'TP53' })
  assert.equal(userlist.bedBFile, 'TP53')

  const rnd = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'rnd' })
  assert.equal('bedBFile' in rnd, false)

  const refseq = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'refseq' })
  assert.equal('bedBFile' in refseq, false)
})

test('buildEnrichmentParams: distanceUp/distanceDown are sent on every submission, regardless of dataset A type', () => {
  for (const aType of ['bed', 'gene', 'count']) {
    const params = buildEnrichmentParams(baseCondition, { ...baseForm, aType, distanceUp: '1000', distanceDown: '2000' })
    assert.equal(params.distanceUp, '1000')
    assert.equal(params.distanceDown, '2000')
  }
})
