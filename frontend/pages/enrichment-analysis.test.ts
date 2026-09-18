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
import {
  applyDatasetBGateTransition,
  buildEnrichmentParams,
  enrichmentFacetFilterOptions,
  qvalCodeToThreshold,
  type EnrichmentFormState,
} from './enrichment-analysis'

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

test('qvalCodeToThreshold: throws on an unparseable code rather than forwarding it as a threshold', () => {
  // Submission-time, not display-only (contrast facet-filter.ts's
  // qvalLabel, which falls back to the raw string): there is no safe guess
  // to fall back to here, so an unrecognized code must fail loudly rather
  // than silently reach WABI as `threshold`.
  assert.throws(() => qvalCodeToThreshold(''), /unparseable qval code/)
  assert.throws(() => qvalCodeToThreshold('not-a-code'), /unparseable qval code/)
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

// ===== applyDatasetBGateTransition — Task C5 =====
//
// Dataset A gene-list gate: Dataset B's RefSeq/user-gene-list options are
// only selectable while Dataset A is a gene list. Closing the gate must not
// silently discard a gene-list-only Dataset B selection — it should be
// restored when the gate reopens, unless the user deliberately abandoned it
// while the gate was still open.

test('applyDatasetBGateTransition: no-op on the very first call (prevGeneMode null)', () => {
  const r = applyDatasetBGateTransition(null, false, 'rnd', null)
  assert.deepEqual(r, { bType: 'rnd', stashed: null })
})

test('applyDatasetBGateTransition: no-op when the gate does not transition', () => {
  // Same mode both sides — e.g. a manual Dataset B change while the gate
  // stays open, or a Dataset A change that does not cross the gene/non-gene
  // boundary (bed -> count).
  const openOpen = applyDatasetBGateTransition(true, true, 'refseq', null)
  assert.deepEqual(openOpen, { bType: 'refseq', stashed: null })

  const closedClosed = applyDatasetBGateTransition(false, false, 'bed', null)
  assert.deepEqual(closedClosed, { bType: 'bed', stashed: null })
})

test('applyDatasetBGateTransition: closing while a gene-only option is selected stashes it and falls back to rnd', () => {
  const refseq = applyDatasetBGateTransition(true, false, 'refseq', null)
  assert.deepEqual(refseq, { bType: 'rnd', stashed: 'refseq' })

  const userlist = applyDatasetBGateTransition(true, false, 'userlist', null)
  assert.deepEqual(userlist, { bType: 'rnd', stashed: 'userlist' })
})

test('applyDatasetBGateTransition: closing while rnd/bed is selected stashes nothing and leaves the selection alone', () => {
  const rnd = applyDatasetBGateTransition(true, false, 'rnd', null)
  assert.deepEqual(rnd, { bType: 'rnd', stashed: null })

  const bed = applyDatasetBGateTransition(true, false, 'bed', null)
  assert.deepEqual(bed, { bType: 'bed', stashed: null })
})

test('applyDatasetBGateTransition: reopening restores a pending stash', () => {
  const r = applyDatasetBGateTransition(false, true, 'rnd', 'userlist')
  assert.deepEqual(r, { bType: 'userlist', stashed: null })
})

test('applyDatasetBGateTransition: reopening with no stash leaves the current selection alone', () => {
  const r = applyDatasetBGateTransition(false, true, 'rnd', null)
  assert.deepEqual(r, { bType: 'rnd', stashed: null })
})

test('applyDatasetBGateTransition: full open -> close -> open cycle restores the abandoned selection', () => {
  // Gate open, user picks 'userlist'.
  let stashed: string | null = null
  // Gate closes (Dataset A switches away from gene list): userlist is
  // gene-only, so it gets stashed and Dataset B falls back to rnd.
  let step = applyDatasetBGateTransition(true, false, 'userlist', stashed)
  assert.deepEqual(step, { bType: 'rnd', stashed: 'userlist' })
  stashed = step.stashed

  // Gate reopens: the stashed 'userlist' comes back.
  step = applyDatasetBGateTransition(false, true, 'rnd', stashed)
  assert.deepEqual(step, { bType: 'userlist', stashed: null })
  stashed = step.stashed

  // A second close/open cycle, starting from the restored 'userlist',
  // behaves the same way rather than drifting.
  step = applyDatasetBGateTransition(true, false, 'userlist', stashed)
  assert.deepEqual(step, { bType: 'rnd', stashed: 'userlist' })
  stashed = step.stashed

  step = applyDatasetBGateTransition(false, true, 'rnd', stashed)
  assert.deepEqual(step, { bType: 'userlist', stashed: null })
})

test('applyDatasetBGateTransition: a selection deliberately abandoned while the gate is open is not resurrected', () => {
  // Gate open with 'refseq' selected (e.g. just restored from an earlier
  // close). The user then manually switches Dataset B to 'rnd' while
  // Dataset A stays a gene list — no gate transition happens at that
  // moment, so applyDatasetBGateTransition is not even invoked; 'rnd' is
  // simply what's live going into the next transition.
  //
  // Gate closes: the live selection is 'rnd', not the abandoned 'refseq',
  // so nothing gene-list-only gets stashed.
  let step = applyDatasetBGateTransition(true, false, 'rnd', null)
  assert.deepEqual(step, { bType: 'rnd', stashed: null })

  // Gate reopens: no stash pending, so 'refseq' is not wrongly restored.
  step = applyDatasetBGateTransition(false, true, 'rnd', step.stashed)
  assert.deepEqual(step, { bType: 'rnd', stashed: null })
})

test('applyDatasetBGateTransition: closing supersedes (does not merge with) a stale prior stash', () => {
  // Defensive case: if a stash were somehow still pending going into a
  // close transition, the live selection at close time wins outright —
  // the stash is replaced or cleared, never merged.
  const r = applyDatasetBGateTransition(true, false, 'bed', 'refseq')
  assert.deepEqual(r, { bType: 'bed', stashed: null })
})

// ===== enrichmentFacetFilterOptions — Task D2, call-site coverage =====
//
// This is the exact function the genome-change handler in init() calls to
// build FacetFilter.init's options (`FacetFilter.init(facet, detail.genome,
// enrichmentFacetFilterOptions(mount))`), not a duplicate of its logic — so
// this test fails if a future edit drops the exclusion at the real call
// site, not just if a standalone helper regresses. See
// frontend/components/facet-filter.test.ts for the underlying
// excludeTrackClasses filter, and peak-browser.test.ts for the mirror-image
// assertion that Peak Browser passes no exclusion at all.

test('enrichmentFacetFilterOptions: excludes Annotation tracks from Enrichment Analysis', () => {
  const mount = {} as Record<'track_class' | 'cell_type_class' | 'qval', HTMLElement>
  const opts = enrichmentFacetFilterOptions(mount)
  assert.deepEqual(opts.excludeTrackClassIds, ['Annotation tracks'])
  assert.equal(opts.render, 'listbox')
  assert.equal(opts.mount, mount)
})
