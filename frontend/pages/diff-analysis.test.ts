// frontend/pages/diff-analysis.test.ts
// Unit tests for the pure logic behind the Diff Analysis job-submission
// payload (Task C1, D7 — corrected mapping supplied by the coordinator after
// the original enrichment-shaped rename table didn't cover this page).
//
// Diff Analysis's WABI mapping differs from Enrichment Analysis's:
// antigenClass here is the diffbind/dmr experiment-type radio (not an
// antigen), and bedAFile/bedBFile are newline-joined ID strings, not arrays.
// Verified against the pre-purge production JS
// (public/js/pj/diff_analysis.js's retrievePostData()).
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildDiffAnalysisParams, type DiffFormState } from './diff-analysis'

const baseForm: DiffFormState = {
  genome: 'hg38',
  analysisType: 'diffbind',
  idsA: ['SRX4099758', 'SRX3481056', 'SRX3481057'],
  idsB: ['SRX3481056', 'SRX3481057'],
  title: 'My project',
  dataATitle: 'dataset A',
  dataBTitle: 'dataset B',
}

test('buildDiffAnalysisParams: renames fields to WABI\'s own names (D7)', () => {
  const params = buildDiffAnalysisParams(baseForm)

  assert.equal(params.genome, 'hg38')
  assert.equal(params.antigenClass, 'diffbind')
  assert.equal(params.bedAFile, 'SRX4099758\nSRX3481056\nSRX3481057')
  assert.equal(params.descriptionA, 'dataset A')
  assert.equal(params.bedBFile, 'SRX3481056\nSRX3481057')
  assert.equal(params.descriptionB, 'dataset B')
  assert.equal(params.title, 'My project')

  // None of the old internal field names should leak onto the wire.
  for (const old of ['analysis', 'dataA_ids', 'dataB_ids', 'dataA_title', 'dataB_title']) {
    assert.equal(Object.prototype.hasOwnProperty.call(params, old), false, `stale field "${old}" leaked into the WABI payload`)
  }

  // Constants/operational fields belong to the next task (WabiService
  // merging them in) and must not be sent from here.
  for (const operational of ['typeA', 'typeB', 'cellClass', 'permTime', 'threshold', 'sbatchOptions', 'address', 'format', 'result']) {
    assert.equal(Object.prototype.hasOwnProperty.call(params, operational), false, `operational field "${operational}" should not be built by the frontend yet`)
  }
})

test('buildDiffAnalysisParams: antigenClass carries the experiment-type radio, dmr included', () => {
  const params = buildDiffAnalysisParams({ ...baseForm, analysisType: 'dmr' })
  assert.equal(params.antigenClass, 'dmr')
})

test('buildDiffAnalysisParams: bedAFile/bedBFile are newline-joined strings, not arrays', () => {
  const params = buildDiffAnalysisParams(baseForm)
  assert.equal(typeof params.bedAFile, 'string')
  assert.equal(typeof params.bedBFile, 'string')
  assert.equal(Array.isArray(params.bedAFile), false)
  assert.equal(Array.isArray(params.bedBFile), false)
})

test('buildDiffAnalysisParams: a single id has no trailing/leading newline', () => {
  const params = buildDiffAnalysisParams({ ...baseForm, idsA: ['SRX000001'], idsB: ['SRX000002'] })
  assert.equal(params.bedAFile, 'SRX000001')
  assert.equal(params.bedBFile, 'SRX000002')
})
