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
import { buildDiffAnalysisParams, createGenomeDatasetStore, resolveAvailabilityUiState, UNAVAILABLE_MESSAGE, type DiffFormState } from './diff-analysis'

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

// ===== Per-genome dataset store (Task C4, D13) =====
// Production holds dataset A/B state per genome tab structurally (genome-
// prefixed DOM ids). This page shares one pair of textareas across all
// genome tabs (the same single-DOM-plus-swap pattern GenomeTabs/FacetFilter
// use elsewhere in this app), so createGenomeDatasetStore is the piece that
// carries the actual guarantee: an id typed while one genome is selected
// must never be read back under a different genome.

test('createGenomeDatasetStore: an unvisited genome reads back blank', () => {
  const store = createGenomeDatasetStore()
  assert.deepEqual(store.get('hg38'), { idsA: '', idsB: '' })
})

test('createGenomeDatasetStore: set then get round-trips for that genome', () => {
  const store = createGenomeDatasetStore()
  store.set('hg38', { idsA: 'SRX1\nSRX2', idsB: 'SRX3' })
  assert.deepEqual(store.get('hg38'), { idsA: 'SRX1\nSRX2', idsB: 'SRX3' })
})

test('createGenomeDatasetStore: values typed under one genome never leak into another', () => {
  const store = createGenomeDatasetStore()
  store.set('hg38', { idsA: 'TESTVALUE_HG38_A', idsB: 'TESTVALUE_HG38_B' })
  // mm10 was never visited/saved - must read back blank, not hg38's values.
  assert.deepEqual(store.get('mm10'), { idsA: '', idsB: '' })
  // TAIR12, likewise.
  assert.deepEqual(store.get('TAIR12'), { idsA: '', idsB: '' })
  // hg38's own values are unaffected by reading other genomes.
  assert.deepEqual(store.get('hg38'), { idsA: 'TESTVALUE_HG38_A', idsB: 'TESTVALUE_HG38_B' })
})

test('createGenomeDatasetStore: clear blanks only the given genome', () => {
  const store = createGenomeDatasetStore()
  store.set('hg38', { idsA: 'SRX1', idsB: 'SRX2' })
  store.set('mm10', { idsA: 'SRX3', idsB: 'SRX4' })
  store.clear('hg38')
  assert.deepEqual(store.get('hg38'), { idsA: '', idsB: '' })
  assert.deepEqual(store.get('mm10'), { idsA: 'SRX3', idsB: 'SRX4' })
})

// ===== Availability UI state (Task C4 part 2, relocated from C3/D12) =====
// GET /jobs/available?type=diff_analysis (routes/jobs.rb -> ComputeRouter,
// see lib/services/compute_router.rb) is the honest source of truth for
// whether a compute backend currently serves this job type. From launch
// until 2026-09-24, ComputeRouter mapped diff_analysis to no backends at
// all (WABI was believed not to serve it), and nothing on this page even
// called this endpoint, so the page showed a complete, fillable form that
// could never submit; the project owner then confirmed WABI serves
// diff-analysis jobs again and had the routing map updated (see
// docs/review-2026-09-23/findings/ui-diff-analysis.md, DA-01). These tests
// pin resolveAvailabilityUiState's decision table, in particular the
// fail-safe choice for a failed check (availability === null): fail OPEN
// (leave the form enabled), because POST /jobs/submit independently
// re-checks ComputeRouter and fails a genuinely-unavailable submission on
// its own, so nothing can be silently wrong -- see the function's own
// comment in diff-analysis.ts for the full reasoning.

test('resolveAvailabilityUiState: available -> submit enabled, notice hidden', () => {
  const ui = resolveAvailabilityUiState({ backend: 'wabi', available: true })
  assert.equal(ui.submitDisabled, false)
  assert.equal(ui.noticeHidden, true)
  assert.equal(ui.noticeText, '')
})

test('resolveAvailabilityUiState: unavailable -> submit disabled, notice shown with a message', () => {
  const ui = resolveAvailabilityUiState({ backend: null, available: false })
  assert.equal(ui.submitDisabled, true)
  assert.equal(ui.noticeHidden, false)
  assert.equal(ui.noticeText, UNAVAILABLE_MESSAGE)
})

test('resolveAvailabilityUiState: a failed check (null) fails OPEN -- same as available', () => {
  const ui = resolveAvailabilityUiState(null)
  assert.equal(ui.submitDisabled, false)
  assert.equal(ui.noticeHidden, true)
  assert.equal(ui.noticeText, '')
})
