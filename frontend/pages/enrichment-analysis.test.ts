// frontend/pages/enrichment-analysis.test.ts
// Unit tests for the pure logic behind the Enrichment Analysis job-submission
// payload (Task C1, D7/D8/D10 in
// docs/superpowers/plans/2026-09-18-post-parity-fixes.md):
//
//  - qvalCodeToThreshold: the qval facet (shared with Peak Browser) exposes
//    the allPeaks_light.<genome>.{05,10,20,50}.bed.gz filename codes as its
//    option values (the code is the exponent: "05" = q < 1E-05 = loosest,
//    "50" = q < 1E-50 = strictest). WABI's `threshold` field wants the
//    *other* encoding production displays for the same four choices
//    (50/100/200/500, larger = stricter). These are two different
//    encodings that happen to share the literal digits "50" for opposite
//    ends of the range: file code "50" names the STRICTEST file, but WABI
//    threshold "50" is the LOOSEST setting — this is exactly the hazard
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
  bedSizeKey,
  buildEnrichmentParams,
  countLines,
  distanceDefaultFor,
  enrichmentFacetFilterOptions,
  prefillSelection,
  estimateSeconds,
  formatEstimate,
  getSeconds,
  qvalCodeToThreshold,
  type EnrichmentFormState,
} from './enrichment-analysis'

// ===== qvalCodeToThreshold — the two-encodings hazard =====

test('qvalCodeToThreshold: "05" (loosest file code, q < 1E-05) -> "50" (loosest WABI threshold label)', () => {
  assert.equal(qvalCodeToThreshold('05'), '50')
})

test('qvalCodeToThreshold: "10" -> "100"', () => {
  assert.equal(qvalCodeToThreshold('10'), '100')
})

test('qvalCodeToThreshold: "20" -> "200"', () => {
  assert.equal(qvalCodeToThreshold('20'), '200')
})

test('qvalCodeToThreshold: "50" (strictest file code, q < 1E-50) -> "500" (strictest WABI threshold label)', () => {
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

test('buildEnrichmentParams: bedBFile is always sent, "empty" when dataset B has no content', () => {
  // This previously asserted the opposite - that bedBFile was omitted for rnd
  // and refseq - which is what made WABI reject every Random-permutation
  // submission. Production always sends the field, substituting the literal
  // string "empty" for a blank textarea (retrieveInputData in its
  // enrichment_analysis.js), and then requires it to be present.
  const bed = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'bed', dataBText: 'chr2\t1\t100' })
  assert.equal(bed.bedBFile, 'chr2\t1\t100')

  const userlist = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'userlist', dataBText: 'TP53' })
  assert.equal(userlist.bedBFile, 'TP53')

  const rnd = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'rnd' })
  assert.equal(rnd.bedBFile, 'empty')

  const refseq = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'refseq' })
  assert.equal(refseq.bedBFile, 'empty')

  const blank = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'bed', dataBText: '   ' })
  assert.equal(blank.bedBFile, 'empty')
})

test('buildEnrichmentParams: distanceUp/distanceDown are sent on every submission, regardless of dataset A type', () => {
  for (const aType of ['bed', 'gene', 'count']) {
    const params = buildEnrichmentParams(baseCondition, { ...baseForm, aType, distanceUp: '1000', distanceDown: '2000' })
    assert.equal(params.distanceUp, '1000')
    assert.equal(params.distanceDown, '2000')
  }
})

// ===== distanceDefaultFor =====
//
// Because the value above is submitted in every mode — including BED mode,
// where the input row is hidden — the default the form carries into a BED
// submission is a real analysis parameter, not just what the user sees.
// Production keys it off dataset A's type: setDistance(0) from positionBed(),
// setDistance(5000) from positionGene() and positionCount().

test('distanceDefaultFor: BED input gets 0, matching production\'s positionBed()', () => {
  assert.equal(distanceDefaultFor('bed'), '0')
})

test('distanceDefaultFor: both gene modes get 5000, matching positionGene()/positionCount()', () => {
  assert.equal(distanceDefaultFor('gene'), '5000')
  assert.equal(distanceDefaultFor('count'), '5000')
})

test('distanceDefaultFor: the value reaches the payload as a string, not a number', () => {
  // buildEnrichmentParams forwards the input's .value verbatim to WABI, so a
  // numeric 0 here would put `0` on the wire where production puts "0".
  const params = buildEnrichmentParams(baseCondition, {
    ...baseForm,
    aType: 'bed',
    distanceUp: distanceDefaultFor('bed'),
    distanceDown: distanceDefaultFor('bed'),
  })
  assert.strictEqual(params.distanceUp, '0')
  assert.strictEqual(params.distanceDown, '0')
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

test('applyDatasetBGateTransition: reopening with no stash takes production\'s RefSeq default', () => {
  // Production's positionGene() force-checks ComparedWithRefseq every time
  // Dataset A becomes a gene list. Carrying BED mode's Random permutation
  // into gene-list mode instead would land on a pairing production models
  // no runtime for, so the estimate panel would go blank on the very first
  // click of "Gene list".
  const r = applyDatasetBGateTransition(false, true, 'rnd', null)
  assert.deepEqual(r, { bType: 'refseq', stashed: null })
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

test('applyDatasetBGateTransition: a userlist selection abandoned while the gate is open is not resurrected', () => {
  // Gate open with 'userlist' selected. The user then manually switches
  // Dataset B to 'rnd' while Dataset A stays a gene list — no gate
  // transition happens at that moment, so applyDatasetBGateTransition is
  // not even invoked; 'rnd' is simply what's live going into the next
  // transition.
  //
  // Gate closes: the live selection is 'rnd', not the abandoned 'userlist',
  // so nothing gene-list-only gets stashed.
  let step = applyDatasetBGateTransition(true, false, 'rnd', null)
  assert.deepEqual(step, { bType: 'rnd', stashed: null })

  // Gate reopens: no stash pending, so the abandoned 'userlist' does not
  // come back — reopening starts again from production's RefSeq default,
  // exactly as it would for a user who had never chosen userlist at all.
  step = applyDatasetBGateTransition(false, true, 'rnd', step.stashed)
  assert.deepEqual(step, { bType: 'refseq', stashed: null })
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

// ===== Estimated run time =====
// The estimate is computed in the browser, exactly as production does it (see
// the long comment above GENOME_SIZE in enrichment-analysis.ts). Every
// expected number below was produced by running production's own
// getSeconds()/estimateTime() arithmetic — transcribed from its
// js/pj/enrichment_analysis.js — not by running the implementation under test
// and recording what it said. A sweep of 1,920 (genome x numRef x dataset x
// mode) combinations agreed with production on the rendered string, and 1,452
// direct getSeconds() calls agreed bit-for-bit; these cases pin the parts of
// that agreement a future edit is most likely to break.

test('getSeconds: the "bed" regression matches production to the last bit', () => {
  assert.equal(getSeconds(500, 5000, 5089448, 'bed'), 80.02945360228571)
})

test('getSeconds: the "rnd" regression (production\'s `default` branch) matches production to the last bit', () => {
  assert.equal(getSeconds(500, 10, 5089448, 'rnd'), 34.58397814748463)
})

test('getSeconds: with everything at zero, "bed" collapses to its k constant scaled by 5/7', () => {
  // Production's expression is `(...) * (5 / 7)`, and 60 * (5/7) is not the
  // same double as (60 * 5) / 7 — hence the literal rather than the tidier
  // arithmetic. That is the point: this pins production's exact rounding.
  assert.equal(getSeconds(0, 0, 0, 'bed'), 42.85714285714286)
  assert.equal(getSeconds(0, 0, 0, 'bed'), 60 * (5 / 7))
})

test('getSeconds: the two branches are genuinely different formulas, not one with a flag', () => {
  assert.notEqual(getSeconds(500, 10, 5089448, 'bed'), getSeconds(500, 10, 5089448, 'rnd'))
})

test('countLines: an empty textarea is zero lines, not one', () => {
  assert.equal(countLines(''), 0)
})

test('countLines: a single trailing newline does not add a line', () => {
  assert.equal(countLines('chr1\t1\t2\n'), 1)
  assert.equal(countLines('chr1\t1\t2'), 1)
  assert.equal(countLines('chr1\t1\t2\nchr2\t3\t4\n'), 2)
})

test('countLines: a blank line in the middle still counts', () => {
  assert.equal(countLines('a\n\nb'), 3)
})

// bedSizeKey feeds /api/bed_sizes, whose keys are the same composite strings
// production's static /data/number_of_lines.json uses. A drift here does not
// throw — it silently misses the table and the panel falls back to an em
// dash — so each component of the key gets its own assertion.
test('bedSizeKey: joins genome, antigen class, cell class and the qval file code', () => {
  assert.equal(
    bedSizeKey({ genome: 'hg38', track_class: 'Histone', cell_type_class: 'Blood', qval: '05' }),
    'hg38,Histone,Blood,05',
  )
})

test('bedSizeKey: uses the qval *file code*, not the WABI threshold qvalCodeToThreshold produces', () => {
  const condition = { genome: 'hg38', track_class: 'Histone', cell_type_class: 'Blood', qval: '50' }
  assert.equal(bedSizeKey(condition), 'hg38,Histone,Blood,50')
  // The submission field for the same choice is "500" — the other encoding.
  assert.equal(qvalCodeToThreshold(condition.qval), '500')
})

test('bedSizeKey: Bisulfite-Seq rows are keyed "bs" — the threshold does not apply to methylation', () => {
  assert.equal(
    bedSizeKey({ genome: 'mm10', track_class: 'Bisulfite-Seq', cell_type_class: 'Liver', qval: '05' }),
    'mm10,Bisulfite-Seq,Liver,bs',
  )
})

test('bedSizeKey: "All cell types" is a real row, not a wildcard', () => {
  assert.equal(
    bedSizeKey({ genome: 'sacCer3', track_class: 'TFs and others', cell_type_class: 'All cell types', qval: '20' }),
    'sacCer3,TFs and others,All cell types,20',
  )
})

const BASE = {
  genome: 'hg38',
  aType: 'bed',
  bType: 'rnd',
  dataAText: '',
  dataBText: '',
  permTime: '1',
  numRef: 5089448,
}

test('estimateSeconds: BED vs random permutation scores dataset B as the permutation multiplier', () => {
  const bed = 'chr1\t100\t200\nchr1\t300\t400\nchr2\t100\t200\n'
  assert.equal(
    estimateSeconds({ ...BASE, dataAText: bed, permTime: '10' }),
    getSeconds(3, 10, 5089448, 'rnd'),
  )
  // ...so raising the multiplier raises the estimate, which is the whole
  // point of showing it next to the permutation radios.
  const x1 = estimateSeconds({ ...BASE, dataAText: bed, permTime: '1' })!
  const x100 = estimateSeconds({ ...BASE, dataAText: bed, permTime: '100' })!
  assert.ok(x100 > x1, `expected x100 (${x100}) > x1 (${x1})`)
})

test('estimateSeconds: BED vs BED uses the "bed" regression on both line counts', () => {
  assert.equal(
    estimateSeconds({
      ...BASE,
      bType: 'bed',
      dataAText: 'chr1\t1\t2\nchr1\t3\t4\n',
      dataBText: 'chr2\t1\t2\nchr2\t3\t4\nchr2\t5\t6\n',
    }),
    getSeconds(2, 3, 5089448, 'bed'),
  )
})

// Production's "one line, no tab" rule: that is a sequence motif, and the
// work it implies is how often a motif that long occurs by chance.
test('estimateSeconds: a single tab-free line is scored as a sequence motif, not as one region', () => {
  assert.equal(
    estimateSeconds({ ...BASE, dataAText: 'GGAATTCC' }),
    getSeconds(3137161264 / Math.pow(4, 8), 1, 5089448, 'rnd'),
  )
})

test('estimateSeconds: a single line *with* a tab is one BED region, not a motif', () => {
  assert.equal(
    estimateSeconds({ ...BASE, dataAText: 'chr1\t100\t200' }),
    getSeconds(1, 1, 5089448, 'rnd'),
  )
})

// Documented production quirk, reproduced deliberately: the motif length is
// the raw textarea length, so a trailing newline counts as a ninth base.
test('estimateSeconds: the motif length is the raw textarea length, trailing newline included', () => {
  assert.equal(
    estimateSeconds({ ...BASE, dataAText: 'GGAATTCC\n' }),
    getSeconds(3137161264 / Math.pow(4, 9), 1, 5089448, 'rnd'),
  )
})

test('estimateSeconds: gene list vs RefSeq compares against every *other* coding gene', () => {
  assert.equal(
    estimateSeconds({ ...BASE, aType: 'gene', bType: 'refseq', dataAText: 'POU5F1\nTP53\nSOX2\n' }),
    getSeconds(3, 18622 - 3, 5089448, 'bed'),
  )
})

test('estimateSeconds: gene list vs a user gene list uses both line counts directly', () => {
  assert.equal(
    estimateSeconds({
      ...BASE,
      aType: 'gene',
      bType: 'userlist',
      dataAText: 'POU5F1\nTP53\n',
      dataBText: 'SOX2\nNANOG\nKLF4\n',
    }),
    getSeconds(2, 3, 5089448, 'bed'),
  )
})

test('estimateSeconds: a gene count table has no dataset B, so B contributes zero lines', () => {
  assert.equal(
    estimateSeconds({ ...BASE, aType: 'count', dataAText: 'id,wt_1,wt_2\nA,1,2\nB,3,4\n' }),
    getSeconds(3, 0, 5089448, 'bed'),
  )
})

test('estimateSeconds: dataset B is ignored entirely in count mode', () => {
  assert.equal(
    estimateSeconds({ ...BASE, aType: 'count', dataAText: 'id,a\nA,1\n', bType: 'bed', dataBText: 'chr1\t1\t2\n' }),
    estimateSeconds({ ...BASE, aType: 'count', dataAText: 'id,a\nA,1\n' }),
  )
})

// The null cases. Production renders each of these as the literal string
// "NaN hr"; returning null here is what lets the panel show an em dash
// instead. These are the only intentional differences from production.
test('estimateSeconds: null when the genome/antigen/cell/qval combination is not in /api/bed_sizes', () => {
  assert.equal(estimateSeconds({ ...BASE, dataAText: 'chr1\t1\t2\n', numRef: undefined }), null)
})

test('estimateSeconds: null for a motif on an assembly production published no genome size for', () => {
  assert.equal(estimateSeconds({ ...BASE, genome: 'TAIR12', dataAText: 'GGAATTCC' }), null)
  // ...but an ordinary BED region on the same assembly still estimates fine,
  // because that path never needs the genome size.
  assert.equal(
    estimateSeconds({ ...BASE, genome: 'TAIR12', dataAText: 'Chr1\t1\t2\n' }),
    getSeconds(1, 1, 5089448, 'rnd'),
  )
})

test('estimateSeconds: null for RefSeq comparison on an assembly with no published gene count', () => {
  assert.equal(
    estimateSeconds({ ...BASE, genome: 'TAIR12', aType: 'gene', bType: 'refseq', dataAText: 'AT1G01010\n' }),
    null,
  )
})

test('estimateSeconds: null for the dataset A/B pairings production\'s own switch has no branch for', () => {
  // Gene list + random permutation is reachable in both UIs and modelled in
  // neither; so is gene list + BED.
  assert.equal(estimateSeconds({ ...BASE, aType: 'gene', bType: 'rnd', dataAText: 'TP53\n' }), null)
  assert.equal(estimateSeconds({ ...BASE, aType: 'gene', bType: 'bed', dataAText: 'TP53\n' }), null)
  // BED + a gene-list-only dataset B (unreachable through the UI's gating).
  assert.equal(estimateSeconds({ ...BASE, bType: 'refseq', dataAText: 'chr1\t1\t2\n' }), null)
})

test('formatEstimate: whole minutes below an hour', () => {
  assert.equal(formatEstimate(0), '0 mins')
  assert.equal(formatEstimate(89), '1 mins')
  assert.equal(formatEstimate(3540), '59 mins')
})

test('formatEstimate: one decimal place of hours from 60 minutes up', () => {
  assert.equal(formatEstimate(3600), '1.0 hr')
  assert.equal(formatEstimate(5700), '1.6 hr')
})

test('formatEstimate: an em dash for null and for a non-finite estimate', () => {
  assert.equal(formatEstimate(null), '—')
  assert.equal(formatEstimate(NaN), '—')
  assert.equal(formatEstimate(Infinity), '—')
})

// ===== prefillSelection =====
//
// Target Genes and the gene search hand this page a gene list over POST.
// Production checks the "Gene list" radio and runs positionGene() before
// filling the textarea; landing gene symbols in a form still set to BED
// would submit them as genomic regions.

test('prefillSelection: no prefill leaves the form in its BED default', () => {
  assert.equal(prefillSelection({}), null)
  assert.equal(prefillSelection({ genes: '', genesetA: '', genesetB: '' }), null)
})

test('prefillSelection: a gene list switches dataset A to genes and dataset B to RefSeq', () => {
  // The RefSeq half is load-bearing: gene list + random permutation is the
  // pairing production models no runtime for, so leaving dataset B alone
  // would land every Target Genes visitor on a blank estimate.
  assert.deepEqual(prefillSelection({ genes: 'POU5F1\nTP53\n' }), {
    aType: 'gene',
    bType: 'refseq',
    aText: 'POU5F1\nTP53\n',
    bText: '',
  })
})

test('prefillSelection: a genesetA/genesetB pair fills both panels as gene lists', () => {
  assert.deepEqual(prefillSelection({ genesetA: 'POU5F1\n', genesetB: 'SOX2\nNANOG\n' }), {
    aType: 'gene',
    bType: 'userlist',
    aText: 'POU5F1\n',
    bText: 'SOX2\nNANOG\n',
  })
})

test('prefillSelection: `genes` wins when both it and the pair are present', () => {
  // Production's if/else-if order. An earlier shape here keyed its else-if
  // off genesetB, which silently dropped `genes` from any request carrying
  // both.
  assert.deepEqual(prefillSelection({ genes: 'MYOD1\n', genesetA: 'POU5F1\n', genesetB: 'SOX2\n' }), {
    aType: 'gene',
    bType: 'refseq',
    aText: 'MYOD1\n',
    bText: '',
  })
})

test('prefillSelection: half a pair is not a prefill — both halves are required', () => {
  assert.equal(prefillSelection({ genesetA: 'POU5F1\n' }), null)
  assert.equal(prefillSelection({ genesetB: 'SOX2\n' }), null)
})
