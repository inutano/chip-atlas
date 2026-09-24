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
  clearedTextareaFor,
  countLines,
  countModeVisibility,
  datasetBRadioVisibility,
  distanceDefaultFor,
  enrichmentFacetFilterOptions,
  exampleFileFor,
  exampleFileForB,
  genomeForTaxonomy,
  prefillSelection,
  estimateSeconds,
  formatEstimate,
  getSeconds,
  NOTE1,
  NOTE2,
  qvalCodeToThreshold,
  resolveAvailabilityUiState,
  UNAVAILABLE_MESSAGE,
  validateDistance,
  validateTitleText,
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

// EA-08: Bisulfite-Seq is a third encoding, not a fifth numeric code — the
// facet offers a single fixed "bs" option for it (facet-filter.ts's
// qvalOptionsFor), and production sends the fixed threshold 999 for it
// (enrichment_analysis.js:970-999) rather than any -10*Log10[Q] figure.
test('qvalCodeToThreshold: "bs" (Bisulfite-Seq NA option) -> "999" (production\'s fixed WABI threshold)', () => {
  assert.equal(qvalCodeToThreshold('bs'), '999')
})

test('qvalCodeToThreshold: "anno" (Annotation tracks) still throws — Enrichment Analysis never offers it', () => {
  // Unlike "bs", "anno" gets no dedicated branch: enrichmentFacetFilterOptions
  // excludes Annotation tracks from the experiment-type list entirely, so
  // qval should never resolve to "anno" here. If it somehow did, falling
  // through to the numeric parse and throwing is the same safe failure as
  // any other unrecognized code.
  assert.throws(() => qvalCodeToThreshold('anno'), /unparseable qval code/)
})

test('qvalCodeToThreshold: throws on an unparseable code rather than forwarding it as a threshold', () => {
  // Submission-time, not display-only (contrast facet-filter.ts's
  // qvalLabel, which falls back to the raw string): there is no safe guess
  // to fall back to here, so an unrecognized code must fail loudly rather
  // than silently reach WABI as `threshold`.
  assert.throws(() => qvalCodeToThreshold(''), /unparseable qval code/)
  assert.throws(() => qvalCodeToThreshold('not-a-code'), /unparseable qval code/)
})

// ===== exampleFileFor — Task 7 (EA-12/EA-13) =====
//
// "Try with example" must load the file that matches whichever dataset A
// mode is currently selected, not always bedA.txt — production's
// putUserData() (enrichment_analysis.js:360-370) switches on the same three
// radio values and never touches the radio itself.

test('exampleFileFor: maps each dataset A mode to its own example file', () => {
  assert.equal(exampleFileFor('bed'), 'bedA.txt')
  assert.equal(exampleFileFor('gene'), 'geneA.txt')
  assert.equal(exampleFileFor('count'), 'countA.txt')
})

// ===== exampleFileForB — Task 8 (R4/EA-17) =====
//
// Dataset B has its own "Try with example" link on production
// (enrichment_analysis.haml:194-197), sitting in the same wrapper as
// dataset B's textarea and file input. Its putComparedWith()
// (enrichment_analysis.js:372-382) switches on the checked comparedWith
// value and loads bedB.txt or geneB.txt. There is deliberately no case for
// rnd/refseq: neither takes input, so the whole wrapper — link included —
// is hidden in those two modes.

test('exampleFileForB: maps each dataset B input mode to its own example file', () => {
  assert.equal(exampleFileForB('bed'), 'bedB.txt')
  assert.equal(exampleFileForB('userlist'), 'geneB.txt')
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

test('buildEnrichmentParams: permTime is always sent, whatever dataset B is', () => {
  // Gating this on bType === 'rnd' made WABI reject every gene-list
  // submission (gene-list mode force-checks dataset B = RefSeq) — 502 from
  // routes/jobs.rb. Production sends it unconditionally.
  for (const bType of ['rnd', 'bed', 'refseq', 'userlist']) {
    const p = buildEnrichmentParams(baseCondition, { ...baseForm, bType, permTime: '10' })
    assert.equal(p.permTime, '10', `permTime missing for dataset B = ${bType}`)
  }
  const blank = buildEnrichmentParams(baseCondition, { ...baseForm, bType: 'refseq', permTime: '' })
  assert.equal(blank.permTime, '1') // production's `permTime > 0 ? permTime : 1`
})

test('buildEnrichmentParams: gene-list mode sends every field production sends', () => {
  const p = buildEnrichmentParams(baseCondition, { ...baseForm, aType: 'gene', bType: 'refseq' })
  assert.deepEqual(Object.keys(p).sort(), [
    'antigenClass', 'bedAFile', 'bedBFile', 'cellClass', 'descriptionA', 'descriptionB',
    'distanceDown', 'distanceUp', 'genome', 'permTime', 'threshold', 'title', 'typeA', 'typeB',
  ])
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

// EA-16: production's retrievePostData() special-cases typeA === "count" —
// it force-overwrites typeB/bedBFile to the literal "empty" regardless of
// whatever dataset B radio happens to be checked underneath the hidden
// panel (enrichment_analysis.js:613-619), and positionCount() stuffs the
// two title inputs with fixed internal values, because panel 5/6 hide the
// real dataset B controls and the title inputs in this mode (EA-15). This
// previously sent whatever dataset B radio/textarea/title happened to be
// selected — the exact regression EA-16 flagged. permTime is deliberately
// NOT part of this special case — see the dedicated test below.
test('buildEnrichmentParams: count mode forces typeB/bedBFile to "empty" and substitutes production\'s internal descriptions', () => {
  const params = buildEnrichmentParams(baseCondition, {
    ...baseForm,
    aType: 'count',
    bType: 'rnd',
    permTime: '10',
    dataBText: 'chr1\t1\t100',
    dataATitle: 'Dataset A',
    dataBTitle: 'Dataset B',
  })
  assert.equal(params.typeB, 'empty')
  assert.equal(params.bedBFile, 'empty')
  assert.equal(params.descriptionA, 'Dataset A from count table header')
  assert.equal(params.descriptionB, 'Dataset B not applicable for count table')
})

// Review round 1, finding 1: production sets permTime unconditionally
// (enrichment_analysis.js:605), before the typeA === "count" special case
// (613-619) even runs — count mode does not remove it. permTime is now sent
// unconditionally regardless of bType (see the "always sent" test above), so
// count mode is not a special case for it either, unlike typeB/bedBFile just
// below, which count mode DOES force to "empty" regardless of dataset B.
test('buildEnrichmentParams: count mode sends permTime unconditionally too, same as every other mode', () => {
  const rnd = buildEnrichmentParams(baseCondition, { ...baseForm, aType: 'count', bType: 'rnd', permTime: '10' })
  assert.equal(rnd.permTime, '10')

  const bed = buildEnrichmentParams(baseCondition, { ...baseForm, aType: 'count', bType: 'bed', dataBText: 'chr2\t1\t100' })
  assert.equal(bed.permTime, '1')
})

test('buildEnrichmentParams: count mode forces "empty" even when dataset B is BED with real content', () => {
  // typeB/bedBFile must come out "empty" regardless of what is sitting in
  // dataset B's (hidden) radio/textarea, not just for the "rnd" default.
  const params = buildEnrichmentParams(baseCondition, {
    ...baseForm,
    aType: 'count',
    bType: 'bed',
    dataBText: 'chr2\t1\t100',
  })
  assert.equal(params.typeB, 'empty')
  assert.equal(params.bedBFile, 'empty')
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

// ===== countModeVisibility — Task 7 review round 1, finding 2 (EA-15) =====
//
// Pure decision logic behind syncDatasetBVisibility's count-mode branch,
// extracted the same way applyDatasetBGateTransition/distanceDefaultFor are
// above, so the panel-visibility rule is pinned by a test without a DOM.

test('countModeVisibility: count mode hides panel 5\'s body and the dataset titles, and shows the note', () => {
  assert.deepEqual(countModeVisibility('count'), {
    panelBodyHidden: true,
    noteHidden: false,
    titlesHidden: true,
  })
})

test('countModeVisibility: bed and gene modes show panel 5\'s body and the dataset titles, and hide the note', () => {
  assert.deepEqual(countModeVisibility('bed'), {
    panelBodyHidden: false,
    noteHidden: true,
    titlesHidden: false,
  })
  assert.deepEqual(countModeVisibility('gene'), {
    panelBodyHidden: false,
    noteHidden: true,
    titlesHidden: false,
  })
})

// ===== datasetBRadioVisibility — Task 8 (R3/EA-14) =====
//
// Production hides the dataset B choices that do not apply to dataset A's
// mode rather than greying them out: positionBed()/positionGene()/
// positionCount() (enrichment_analysis.js:394-486) run show()/hide() over
// the .panel-input wrappers, so the rows really leave the layout. This page
// used to toggle `disabled` on Refseq/Gene list and never gate Random/BED
// at all, which is what the owner reported as "panel 5 does not change".

test('datasetBRadioVisibility: BED mode shows Random and BED, hides the gene-list-only rows', () => {
  assert.deepEqual(datasetBRadioVisibility('bed'), {
    rndHidden: false,
    bedHidden: false,
    refseqHidden: true,
    userlistHidden: true,
  })
})

test('datasetBRadioVisibility: gene-list mode shows Refseq and Gene list, hides Random and BED', () => {
  assert.deepEqual(datasetBRadioVisibility('gene'), {
    rndHidden: true,
    bedHidden: true,
    refseqHidden: false,
    userlistHidden: false,
  })
})

// Count mode has no dataset B at all — countModeVisibility above already
// hides the whole #dataB-panel-body — but the four rows still report
// hidden so the two rules can never disagree about a row's state.
test('datasetBRadioVisibility: count mode hides all four rows', () => {
  assert.deepEqual(datasetBRadioVisibility('count'), {
    rndHidden: true,
    bedHidden: true,
    refseqHidden: true,
    userlistHidden: true,
  })
})

// ===== clearedTextareaFor — Task 8 (R5) =====
//
// Production's eraseTextarea() (enrichment_analysis.js:76-90, 93-110) is
// group-scoped: the dataset A radio handler erases dataset A's textarea and
// the dataset B radio handler erases dataset B's, each unconditionally and
// neither touching the other. That asymmetry is load-bearing — switching
// dataset A force-reassigns dataset B's radio through a programmatic
// checked = true, which fires no `change` event, so dataset B's text
// survives a dataset A switch (verified live on production, both
// directions). Hence the mapping below has no "clear both" case.

test('clearedTextareaFor: each radio group clears only its own dataset\'s textarea', () => {
  assert.equal(clearedTextareaFor('dataA-type'), 'dataA-text')
  assert.equal(clearedTextareaFor('dataB-type'), 'dataB-text')
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

// TAIR12 is the one genome in the tabs that production has no tab for, so
// both its constants had to be derived from the assembly ChIP-Atlas publishes
// rather than copied. These pin the derived values at the two places they are
// the only thing standing between the panel and an em dash.
test('estimateSeconds: a motif on TAIR12 uses the assembly size summed from its faidx index', () => {
  assert.equal(
    estimateSeconds({ ...BASE, genome: 'TAIR12', dataAText: 'GGAATTCC' }),
    getSeconds(142481245 / Math.pow(4, 8), 1, 5089448, 'rnd'),
  )
})

test('estimateSeconds: RefSeq comparison on TAIR12 uses its protein-coding locus count', () => {
  assert.equal(
    estimateSeconds({ ...BASE, genome: 'TAIR12', aType: 'gene', bType: 'refseq', dataAText: 'AT1G01010\n' }),
    getSeconds(1, 26867 - 1, 5089448, 'bed'),
  )
})

// The fallback the two tables above still need. Both paths reach for a
// per-assembly constant, and production divides by `undefined` when it has
// none — rendering the string "NaN hr". danRer11 stands in for any assembly
// added to the tabs before someone adds its two constants.
test('estimateSeconds: null for a motif on an assembly missing from GENOME_SIZE', () => {
  assert.equal(estimateSeconds({ ...BASE, genome: 'danRer11', dataAText: 'GGAATTCC' }), null)
  // ...but an ordinary BED region on the same assembly still estimates fine,
  // because that path never needs the genome size.
  assert.equal(
    estimateSeconds({ ...BASE, genome: 'danRer11', dataAText: 'chr1\t1\t2\n' }),
    getSeconds(1, 1, 5089448, 'rnd'),
  )
})

test('estimateSeconds: null for RefSeq comparison on an assembly missing from NUM_GENES', () => {
  assert.equal(
    estimateSeconds({ ...BASE, genome: 'danRer11', aType: 'gene', bType: 'refseq', dataAText: 'myod1\n' }),
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

// ===== validateTitleText / validateDistance — Task 7 (EA-27) =====
//
// Production's evaluateText()/isValid() (enrichment_analysis.js:639-689),
// run just before every submission, rejects a Project title / User data
// title / Compared data title containing anything outside alphanumerics,
// space, underscore, period and hyphen, and rejects a TSS distance that is
// not a bare positive integer. Exported as pure, DOM-free helpers — same
// reasoning as buildEnrichmentParams above — so production's exact message
// text is pinned without a live submit button.

test('validateTitleText: accepts alphanumerics, space, underscore, period and hyphen', () => {
  assert.equal(validateTitleText('Project title', 'My project_1.2-3 ABC'), null)
})

test('validateTitleText: an empty string is valid — production only checks characters, not length', () => {
  assert.equal(validateTitleText('Project title', ''), null)
})

test('validateTitleText: rejects "&", with production\'s exact message and the given label', () => {
  assert.equal(
    validateTitleText('Project title', 'My & project'),
    'Invalid characters are detected in Project title. Acceptable characters are:\n' +
      '- alphanumerics (abcABC123)\n- space ( )\n- underscore (_)\n- period (.)\n- hyphen (-)',
  )
})

test('validateTitleText: the label in the message is whichever one is passed in', () => {
  assert.match(
    validateTitleText('User data title', '<script>')!,
    /^Invalid characters are detected in User data title\. /,
  )
  assert.match(
    validateTitleText('Compared data title', '<script>')!,
    /^Invalid characters are detected in Compared data title\. /,
  )
})

test('validateDistance: accepts a bare positive integer, including zero', () => {
  assert.equal(validateDistance('5000'), null)
  assert.equal(validateDistance('0'), null)
})

test('validateDistance: rejects anything that is not all digits, with production\'s exact message', () => {
  assert.equal(
    validateDistance('-1'),
    'Invalid characters are detected in Distance from TSS. Acceptable characters are:\n' +
      '- positive integer (1,2,3,..)',
  )
  assert.notEqual(validateDistance('5000.5'), null)
  assert.notEqual(validateDistance(''), null)
  assert.notEqual(validateDistance('abc'), null)
})

// ===== genomeForTaxonomy — EA-35 =====
//
// A POST prefill's `taxonomy` (an NCBI taxid) is production's mechanism for
// an external service — Target Genes, the gene search — to hand over a gene
// list already scoped to one species. Production's taxidMap
// (enrichment_analysis.js:31-62) points each taxid at that species'
// *older* assembly (hg19, mm9, dm3, ce10 — genomeVersions[0]); this app
// offers only one assembly per species (config/genomes.yml), so the map is
// remapped to whichever one this app actually has a tab for.

test('genomeForTaxonomy: maps each of production\'s six taxids, plus A. thaliana, to the assembly this app offers', () => {
  assert.equal(genomeForTaxonomy('9606'), 'hg38')
  assert.equal(genomeForTaxonomy('10090'), 'mm10')
  assert.equal(genomeForTaxonomy('10116'), 'rn6')
  assert.equal(genomeForTaxonomy('7227'), 'dm6')
  assert.equal(genomeForTaxonomy('6239'), 'ce11')
  assert.equal(genomeForTaxonomy('4932'), 'sacCer3')
  assert.equal(genomeForTaxonomy('3702'), 'TAIR12')
})

test('genomeForTaxonomy: trims surrounding whitespace before looking up the taxid', () => {
  assert.equal(genomeForTaxonomy(' 10090 '), 'mm10')
})

test('genomeForTaxonomy: an unknown, empty, or missing taxid is null, never a guess', () => {
  assert.equal(genomeForTaxonomy('1234567'), null)
  assert.equal(genomeForTaxonomy(''), null)
  assert.equal(genomeForTaxonomy(undefined), null)
})

// ===== resolveAvailabilityUiState / UNAVAILABLE_MESSAGE — EA-36 / SHELL-39 =====
//
// Copied from diff-analysis.ts's resolveAvailabilityUiState (per-page
// duplication - see colo-result.ts's header comment) with this page's own
// message text, restoring the page-load "is the compute backend up" check
// production's window.onload performed (fetching /wabi_endpoint_status and
// disabling its submit button + alerting when it wasn't "chipatlas"), which
// this page had no equivalent of before this task.

test('resolveAvailabilityUiState: available leaves the form usable and the notice hidden', () => {
  assert.deepEqual(resolveAvailabilityUiState({ backend: 'wabi', available: true }), {
    submitDisabled: false,
    noticeHidden: true,
    noticeText: '',
  })
})

test('resolveAvailabilityUiState: a failed check (null) fails open, same as diff-analysis.ts', () => {
  assert.deepEqual(resolveAvailabilityUiState(null), {
    submitDisabled: false,
    noticeHidden: true,
    noticeText: '',
  })
})

test('resolveAvailabilityUiState: unavailable disables submit and shows this page\'s own message', () => {
  assert.deepEqual(resolveAvailabilityUiState({ backend: null, available: false }), {
    submitDisabled: true,
    noticeHidden: false,
    noticeText: UNAVAILABLE_MESSAGE,
  })
})

test('UNAVAILABLE_MESSAGE: matches the task brief\'s exact wording', () => {
  assert.equal(
    UNAVAILABLE_MESSAGE,
    'Enrichment analysis is currently unavailable due to the backend server issue. See the maintenance schedule on the top page.',
  )
})

// ===== NOTE2 — EA-22 =====
//
// The A:BED / B:BED ⓘ help text's "Acceptable genome assemblies" list must
// match the seven tabs this app actually offers (config/genomes.yml), not
// production's ten. NOTE1's identifier and nomenclature lines gained the
// A. thaliana entries the pipeline team specified on 2026-09-24 (see the
// NOTE1 test at the end of this file).

test('NOTE2: lists every offered assembly, including the newly-added TAIR12', () => {
  assert.match(NOTE2, /hg38 \(H\. sapiens\)/)
  assert.match(NOTE2, /mm10 \(M\. musculus\)/)
  assert.match(NOTE2, /rn6 \(R\. norvegicus\)/)
  assert.match(NOTE2, /dm6 \(D\. melanogaster\)/)
  assert.match(NOTE2, /ce11 \(C\. elegans\)/)
  assert.match(NOTE2, /sacCer3 \(S\. cerevisiae\)/)
  assert.match(NOTE2, /TAIR12 \(A\. thaliana\)/)
})

test('NOTE2: does not list the retired assemblies this app no longer offers', () => {
  for (const retired of ['hg19', 'mm9', 'dm3', 'ce10']) {
    assert.equal(NOTE2.includes(retired), false, `NOTE2 should not mention retired assembly "${retired}"`)
  }
})

// ===== NOTE1 — A. thaliana identifiers (pipeline team, 2026-09-24) =====
test('NOTE1: names the AGI locus code as the A. thaliana Ensembl-style ID and TAIR as its nomenclature', () => {
  assert.match(NOTE1, /Ensembl IDs \(e\.g\. ENSG00000204531; AT1G01010 for A\. thaliana\)/)
  assert.match(NOTE1, /\n  S\. cerevisiae: SGD\n  A\. thaliana: TAIR\n/)
})
