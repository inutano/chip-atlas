// frontend/pages/enrichment-analysis.ts
// GenomeTabs + FacetFilter (list-box mode, six-panel grid) + dataset A/B inputs
// (BED/genes/count, file upload, "Try with example") + estimated run time + job submit.
//
// The "Track type (optional)" and "Cell type (optional)" panels use the same
// "type to search" + ListBox pairing as frontend/pages/peak-browser.ts, for
// the same reason documented there: Autocomplete drives the *same* <select>
// FacetFilter owns (via a native `change` event) instead of building a second,
// competing ListBox, so the cascade and FacetFilter.getCondition() stay correct.

import { GenomeTabs } from '../components/genome-tabs'
import { FacetFilter, type FacetCondition, type FacetFilterOptions } from '../components/facet-filter'
import { Autocomplete } from '../components/autocomplete'
import { initInfoPopovers } from '../components/info-popover'
import { submitJob, getBedSizes, type BedSizes } from '../api/client'

interface PageData {
  genomes: Record<string, string>
  prefill: {
    taxonomy?: string
    genes?: string
    genesetA?: string
    genesetB?: string
  }
}

// Copy lifted verbatim from production's js/pj/enrichment_analysis.js
// helpText object (the note1/note2 fragments are appended exactly as
// production's own $(".infoBtn").click handler concatenates them).
const NOTE1 =
  'Acceptable identifiers:\n  Official gene symbols (e.g. POU5F1)\n  Ensembl IDs (e.g. ENSG00000204531)\n  Uniprot IDs (e.g. Q01860)\n  RefSeq gene IDs (e.g. NM_002701)\n\nOfficial gene symbols must be entered according to following nomenclatures:\n  H. sapiens: HGNC\n  M. musculus: MGI\n  R. norvegicus: RGD\n  D. melanogaster: FlyBase\n  C. elegans: WormBase\n  S. cerevisiae: SGD\n\nAcceptable example:\n  POU5F1\n  TP53\n\nBad example:\n  OCT4\n  p53'
const NOTE2 =
  'Example:\n  chr1<tab>531435<tab>543845\n  chr2<tab>738543<tab>742321\n\nAcceptable genome assemblies:\n    hg19, hg38 (H. sapiens)\n    mm9, mm10 (M. musculus)\n    rn6 (R. norvegicus)\n    dm3, dm6 (D. melanogaster)\n    ce10, ce11 (C. elegans)\n    sacCer3 (S. cerevisiae)\n\n'

const HELP_TEXT: Record<string, string> = {
  threshold:
    'Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If set to 50, peaks with Q values < 1E-05 are used to evaluate overlap with data sets A and, when available, B. Ignore if experiment type is set to Bisulfite-seq.',
  'genomic-regions':
    'Check this to search for common epigenetic features within given genomic regions (UCSC BED format).\n\n' + NOTE2,
  'gene-list':
    'Check this to search for common epigenetic features around given genes.\n\n' + NOTE1,
  'gene-count-table':
    'Check this to upload a two-group gene count table (raw integer counts in CSV or TSV) with a header to search for common epigenetic features around highly expressed genes in each group.\n\nThe first column of the header is ignored. The other columns in the header specify the sample names for the corresponding columns (e.g., "wt_1" indicates replicate 1 of the "wt" group; the replicate number should be appended to the sample name, following an underscore). \n\nThe first column of the count table should contain gene names or IDs.\n\n' +
    NOTE1,
  permutation:
    'Check this to compare ‘dataset A’ with a random background. In this case, each genomic location of ‘dataset A’ is permuted on a random chromosome at a random position for the specified times. Increasing the permutation times will provide a highly randomized background, or a high quality statistical test, but the calculation time will be longer.',
  'dataset-b-bed':
    "Check this to compare 'dataset A' with another dataset (UCSC BED format).\n\n" + NOTE2,
  'analysis-title':
    'Enter a title for this submission.\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  // Both topics are lifted verbatim from production's helpText object. `tss`
  // has never had a reachable info-btn in production either (its DOM id,
  // `#{genome}TSS`, matches no element back to the 2015 original — only
  // `#{genome}DistTSS` -> `disttss` is wired to a real button); it is kept
  // here anyway so the restored topic set matches production's, not because
  // anything in this page currently triggers it.
  tss:
    'To search for common epigenetic features around given genes, specify the distance range from the Transcription Start Sites (TSS).\nDefault is between -5000 and +5000 bp from the TSS.',
  disttss:
    'To search for common epigenetic features around given genes, specify the distance range from the Transcription Start Sites (TSS).\n\nDefault is between -5000 and +5000 bp from the TSS. Specifying TSS ± 1000 bp, ± 5000 bp, or ± 10000 bp can accelerate the calculation by using a predefined gene-feature network.\n\n',
}

// WABI's qval facet (shared with Peak Browser via FacetFilter) exposes the
// allPeaks_light.<genome>.{05,10,20,50}.bed.gz filename codes as its option
// values — Peak Browser needs exactly that code to look up bed files. WABI's
// job-submission `threshold` field wants the *other* encoding production
// displays for the same four choices (50/100/200/500, i.e. -10*Log10[Q]).
// This mirrors facet-filter.ts's private qvalLabel() (duplicated rather than
// imported — see colo-result.ts's header comment on why each frontend/pages
// entry point duplicates small shared helpers instead of a shared module).
// Conflating the two encodings is the exact hazard this function exists to
// prevent: sending "50" (the strictest *file code*, q < 1E-50) unconverted
// would land as threshold=50, which is actually WABI's LOOSEST threshold
// setting (q < 1E-05) — the opposite end of the range from what was meant.
//
// Unlike qvalLabel (display-only — the worst case there is a mislabeled
// dropdown), this feeds a live submission to WABI. An unparseable code has
// no safe fallback to guess at, so this throws rather than silently
// forwarding the raw (wrong-encoding) code as if it were already a
// threshold — the same trap that put the file-suffix code on the wire as
// `qval` in the first place. In practice the facet is always populated
// from /api/qval_range's four fixed codes ("05"/"10"/"20"/"50"), so this is
// unreachable today; but "unreachable today" is exactly the assumption
// that let that original bug ship, so this does not rely on it silently.
export function qvalCodeToThreshold(code: string): string {
  const n = parseInt(code, 10)
  if (Number.isNaN(n)) {
    throw new Error(`qvalCodeToThreshold: unparseable qval code "${code}" — refusing to guess a WABI threshold`)
  }
  return String(n * 10)
}

let currentGenome = ''

function $(id: string): HTMLElement {
  const el = document.getElementById(id)
  if (!el) throw new Error(`Missing #${id}`)
  return el
}

function readPageData(): PageData {
  const el = document.getElementById('page-data')
  if (!el || !el.textContent) throw new Error('Missing #page-data')
  return JSON.parse(el.textContent) as PageData
}

function readFileToTextarea(input: HTMLInputElement, textarea: HTMLTextAreaElement): void {
  input.addEventListener('change', () => {
    const file = input.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => {
      textarea.value = String(reader.result || '')
      // The file picker's own `change` fired before FileReader finished, so
      // the estimate listener saw an empty textarea. Announce the contents.
      textarea.dispatchEvent(new Event('input', { bubbles: true }))
    }
    reader.readAsText(file)
  })
}

function getCheckedValue(name: string): string {
  const r = document.querySelector<HTMLInputElement>(`input[name="${name}"]:checked`)
  return r?.value || ''
}

// Task C5: module-level so the gate-transition state survives across calls
// to syncDatasetBVisibility (one per dataA-type/dataB-type change event).
// prevDatasetBGateOpen starts null so the very first call — page load,
// before any user interaction — never counts as a transition.
let prevDatasetBGateOpen: boolean | null = null
let stashedDatasetBSelection: string | null = null
// Dataset A's type as of the last syncDatasetBVisibility call — see the
// distance reset in it for why this is tracked separately from the gate above.
let prevDataAType: string | null = null

// Pure decision logic for Task C5, kept separate from the DOM reads/writes
// in syncDatasetBVisibility below — the same separation buildEnrichmentParams
// uses so it can be unit-tested without a DOM (see enrichment-analysis.test.ts).
//
// Dataset B's RefSeq/user-gene-list options are gene-list-mode only; when
// Dataset A stops being a gene list those two get disabled, and whichever of
// them was selected can no longer stay selected. Forcing Dataset B back to
// Random permutation at that point is still correct — but doing *only* that
// throws the user's choice away for good. This stashes the discarded
// selection instead and restores it the next time gene-list mode reopens.
//
// With nothing stashed, reopening takes RefSeq rather than leaving whatever
// BED mode was using. That is production's behaviour — positionGene()
// force-checks ComparedWithRefseq and unchecks the other three every time
// Dataset A becomes a gene list — and it is not a neutral difference: gene
// list + random permutation is a pairing production models no runtime for,
// so the estimate panel has nothing to show for it (see estimateSeconds),
// and it is exactly where a user lands by simply picking "Gene list".
//
// The "did the user abandon it on purpose" case is handled by *what* gets
// stashed, not by tracking history: only the option live at the instant the
// gate closes is a candidate for restoring. If the user manually switches
// Dataset B to Random permutation while the gate is still open (no
// open/close transition happening at that moment, so this function isn't
// even called), that is what's live when the gate next closes — so nothing
// gene-list-only is stashed, and reopening does not resurrect the option
// they walked away from — it starts again from the RefSeq default above.
// Repeated open/close cycles each re-derive the stash from whatever is live
// at that moment, so they compound correctly instead of drifting.
export function applyDatasetBGateTransition(
  prevGeneMode: boolean | null,
  isGeneMode: boolean,
  currentBType: string,
  stashed: string | null,
): { bType: string; stashed: string | null } {
  if (prevGeneMode === null || prevGeneMode === isGeneMode) {
    // No transition: leave the current selection and stash untouched.
    return { bType: currentBType, stashed }
  }
  if (prevGeneMode && !isGeneMode) {
    // Gate just closed. A gene-list-only selection can't survive; stash it
    // and fall back to Random permutation. Anything else (rnd/bed) is
    // already valid with the gate closed, so there's nothing to stash —
    // and any previously stashed value is now stale (superseded by
    // whichever selection was actually live) and must be dropped.
    const isGeneOnly = currentBType === 'refseq' || currentBType === 'userlist'
    return isGeneOnly ? { bType: 'rnd', stashed: currentBType } : { bType: currentBType, stashed: null }
  }
  // Gate just reopened. Restore the stash if one is pending; otherwise take
  // production's own gene-list default, RefSeq.
  return stashed ? { bType: stashed, stashed: null } : { bType: 'refseq', stashed: null }
}

/**
 * What a POST prefill should set the form to, before any DOM is touched.
 *
 * Everything arriving this way is a gene list — the senders are Target Genes
 * and the gene search — so production checks the "Gene list" radio and runs
 * positionGene() before filling the textarea, rather than dropping gene
 * symbols into a form still set to BED. positionGene() also force-checks
 * RefSeq for dataset B; that matters on this path because syncDatasetBVisibility
 * cannot supply the default itself (its first call sees no gate transition),
 * and without it a visitor arriving from Target Genes would land on gene list
 * + random permutation, the one pairing with no estimate.
 *
 * `genes` wins over the genesetA/genesetB pair, matching production's
 * if/else-if.
 */
export function prefillSelection(prefill: PageData['prefill']): {
  aType: string
  bType: string
  aText: string
  bText: string
} | null {
  if (prefill.genes) {
    return { aType: 'gene', bType: 'refseq', aText: prefill.genes, bText: '' }
  }
  if (prefill.genesetA && prefill.genesetB) {
    // Dataset B's "Gene list" option — production's ComparedWithUserlist.
    return { aType: 'gene', bType: 'userlist', aText: prefill.genesetA, bText: prefill.genesetB }
  }
  return null
}

/**
 * The TSS distance range production puts in the form for each dataset A type:
 * positionBed() calls setDistance(0), positionGene() and positionCount() both
 * call setDistance(5000). Production's page ships with 0 in the markup too,
 * matching its initial BED mode (views/enrichment_analysis.erb does the same).
 *
 * This is not cosmetic. buildEnrichmentParams submits distanceUp/distanceDown
 * on every job regardless of mode — including BED mode, where the row is
 * hidden — so a BED submission carrying 5000 is a different analysis request
 * from production's, not just a different-looking form.
 */
export function distanceDefaultFor(aType: string): string {
  return aType === 'bed' ? '0' : '5000'
}

function syncDatasetBVisibility(): void {
  const aType = getCheckedValue('dataA-type')
  const isGeneMode = aType === 'gene'

  const transition = applyDatasetBGateTransition(
    prevDatasetBGateOpen,
    isGeneMode,
    getCheckedValue('dataB-type'),
    stashedDatasetBSelection,
  )
  stashedDatasetBSelection = transition.stashed
  prevDatasetBGateOpen = isGeneMode

  const bType = transition.bType
  if (getCheckedValue('dataB-type') !== bType) {
    (document.getElementById(`dataB-${bType}`) as HTMLInputElement).checked = true
  }

  // Refseq + userlist are gene-list-mode only
  ;(document.getElementById('dataB-refseq') as HTMLInputElement).disabled = !isGeneMode
  ;(document.getElementById('dataB-userlist') as HTMLInputElement).disabled = !isGeneMode

  // Random permutation row visible only when dataset B = rnd
  ;($('permutation-row') as HTMLElement).hidden = bType !== 'rnd'

  // Textarea + file picker visible when dataset B needs content (bed or userlist)
  const needsInput = bType === 'bed' || bType === 'userlist'
  ;(document.getElementById('dataB-text') as HTMLElement).hidden = !needsInput
  ;(document.getElementById('dataB-file') as HTMLElement).hidden = !needsInput

  // Helper note
  const note = $('dataB-note')
  if (bType === 'rnd') note.textContent = 'Random permutation needs no input.'
  else if (bType === 'refseq') note.textContent = 'All Refseq coding genes (excluding dataset A) are used.'
  else if (needsInput) note.textContent = ''
  else note.textContent = ''

  // Distance from TSS only makes sense once dataset A resolves to genes
  // (gene list or gene count table) — production shows it in exactly those
  // two modes and hides it for plain BED input.
  ;($('distance-tss-row') as HTMLElement).hidden = aType === 'bed'

  // Reset the range only when dataset A's type actually changed. This
  // function also runs for dataset B changes, and production's setDistance()
  // fires only from positionBed/Gene/Count — i.e. only off the bedORGene
  // radio. Resetting on every call would wipe a range the user had just
  // typed the moment they touched a dataset B radio.
  if (prevDataAType !== aType) {
    prevDataAType = aType
    const distance = distanceDefaultFor(aType)
    ;($('distance-up') as HTMLInputElement).value = distance
    ;($('distance-down') as HTMLInputElement).value = distance
  }
}

// ===== Estimated run time =====
// Production computes this entirely in the browser — see its
// js/pj/enrichment_analysis.js timeCalculate() / estimateTime() / getSeconds().
// There is no server round trip and no queue introspection: the estimate is a
// closed-form regression over three numbers (lines in dataset A, lines in
// dataset B, and how many peak-file lines the chosen genome/antigen/cell/qval
// combination holds), so it is reproduced here rather than bolted onto
// POST /jobs/estimated_time. That endpoint models only diff analysis's
// 'dmr'/'diffbind' formulas (routes/jobs.rb), which production also computes
// server-side; adding an enrichment branch there would introduce a DB round
// trip production does not make, for a number it already has in hand.
//
// The regression coefficients, the k constants, the 5/7 and 1.8/0.85 factors
// and both lookup tables below are transcribed verbatim from production. They
// are fitted constants with no derivation to check them against, so they are
// copied rather than re-derived, and kept in production's own shape so the two
// stay diffable.

/**
 * Genome sizes in bp, verbatim from production's `genomesize` table. Used only
 * for the sequence-motif case below. Production's table predates this app's
 * genome list on both ends: it still carries hg19/mm9/dm3/ce10, which the tabs
 * no longer offer, and it has no entry for TAIR — kept as-is so a diff against
 * production shows only real drift.
 */
const GENOME_SIZE: Record<string, number> = {
  ce10: 100286070,
  ce11: 100286070,
  dm3: 168736537,
  dm6: 168736537,
  hg19: 3137161264,
  hg38: 3137161264,
  mm9: 2725765481,
  mm10: 2725765481,
  sacCer3: 12157105,
  rn6: 2870182909,
}

/** RefSeq coding-gene counts, verbatim from production's `numGenes` table. */
const NUM_GENES: Record<string, number> = {
  ce10: 17958,
  ce11: 17958,
  dm3: 12635,
  dm6: 12635,
  hg19: 18622,
  hg38: 18622,
  mm9: 19909,
  mm10: 19909,
  sacCer3: 5809,
  rn6: 23425,
}

/**
 * Key into /api/bed_sizes, which is this app's equivalent of production's
 * static /data/number_of_lines.json and uses the identical
 * `genome,antigenClass,cellClass,qval` composite key.
 *
 * Two details production's timeCalculate() handles and this must too:
 * Bisulfite-Seq rows are keyed with the literal "bs" (the significance
 * threshold does not apply to methylation data, so there is one row per
 * genome/cell class instead of four), and the q-value component is the
 * *file code* ("05"/"10"/"20"/"50"), not the -10*Log10[Q] threshold. Production
 * divides its own option value by 10 to get there; FacetFilter already carries
 * the file code, so no conversion happens here. Do not reuse
 * qvalCodeToThreshold() for this — it converts in the opposite direction, for
 * the WABI submission field.
 */
export function bedSizeKey(
  condition: Pick<FacetCondition, 'genome' | 'track_class' | 'cell_type_class' | 'qval'>,
): string {
  const qval = condition.track_class === 'Bisulfite-Seq' ? 'bs' : condition.qval
  return [condition.genome, condition.track_class, condition.cell_type_class, qval].join(',')
}

/**
 * Production's line count: an empty textarea is 0 lines, and one trailing
 * newline is ignored so that "chr1\t1\t2\n" counts as one region, not two.
 */
export function countLines(text: string): number {
  if (text.length === 0) return 0
  return text.replace(/\n$/, '').split('\n').length
}

/**
 * A single line with no tab in it is a sequence motif rather than a BED record.
 * Production estimates the work that implies from how often a motif that long
 * turns up by chance across the genome.
 *
 * `text.length` is production's own expression, and it measures the raw
 * textarea contents — so a motif typed with a trailing newline counts one
 * character longer, and the estimate comes out ~4x smaller. That is
 * reproduced rather than corrected: these are estimates shown side by side
 * with production's, and a silent arithmetic divergence would be harder to
 * account for than the quirk.
 *
 * Returns null when the genome has no entry in GENOME_SIZE. Production would
 * divide by `undefined` here and render the string "NaN hr" (NaN < 60 is
 * false, so it even takes the hours branch); an em dash is the honest answer
 * for "no published figure for this assembly".
 */
function motifLineCount(genome: string, text: string, lines: number): number | null {
  if (lines !== 1 || text.includes('\t')) return lines
  const size = GENOME_SIZE[genome]
  if (size === undefined) return null
  return size / Math.pow(4, text.length)
}

/** Production's getSeconds(). "rnd" is its `default` branch. */
export function getSeconds(
  numLinesA: number,
  numLinesB: number,
  numRef: number,
  type: 'bed' | 'rnd',
): number {
  if (type === 'bed') {
    const a = numRef * 8.23e-11 + 1.47e-2
    const b = numRef * 4.72e-11 + 7.24e-3
    const c = (numLinesA + numLinesB) * 6.75e-11 + 1.02e-6
    const k = 60
    return (k + a * numLinesA + b * numLinesB + c * numRef) * (5 / 7)
  }
  const a = numRef * 3.02e-12 + 1.13e-4
  const c = (numLinesA + numLinesA * numLinesB) * 3.02e-12 + 2.06e-6
  const k = 20
  return (
    1.8 *
    Math.pow(k + a * (Math.pow(0.8 * numLinesA, 1.52) + numLinesA * numLinesB) + c * numRef, 0.85)
  )
}

export interface EstimateInput {
  genome: string
  aType: string
  bType: string
  /** Raw textarea contents, untrimmed — see motifLineCount. */
  dataAText: string
  dataBText: string
  permTime: string
  /** /api/bed_sizes lookup; undefined when the combination has no peaks. */
  numRef: number | undefined
}

/**
 * Production's estimateTime(), minus its final formatting step.
 *
 * Returns null for every combination production leaves `seconds` undefined in
 * (and therefore renders as "NaN hr"): an unknown genome/antigen/cell/qval
 * combination, and the dataset A/B pairings its switch has no branch for —
 * notably gene list + random permutation, which this app's dataset B panel
 * allows and production's own panel does too. Callers render null as an em
 * dash. This is the one deliberate behavioural difference from production
 * here; every reachable combination it does compute is computed identically.
 */
export function estimateSeconds(input: EstimateInput): number | null {
  const numRef = input.numRef
  if (numRef === undefined || !Number.isFinite(numRef)) return null

  const linesA = countLines(input.dataAText)
  const linesB = countLines(input.dataBText)

  switch (input.aType) {
    case 'bed': {
      const motifA = motifLineCount(input.genome, input.dataAText, linesA)
      if (motifA === null) return null
      if (input.bType === 'rnd') {
        // Dataset B's line count is the permutation multiplier, not any text.
        return getSeconds(motifA, Number(input.permTime), numRef, 'rnd')
      }
      if (input.bType === 'bed') {
        const motifB = motifLineCount(input.genome, input.dataBText, linesB)
        if (motifB === null) return null
        return getSeconds(motifA, motifB, numRef, 'bed')
      }
      return null
    }
    case 'gene': {
      if (input.bType === 'refseq') {
        const total = NUM_GENES[input.genome]
        if (total === undefined) return null
        // Dataset B is every coding gene *except* the ones in dataset A.
        return getSeconds(linesA, total - linesA, numRef, 'bed')
      }
      if (input.bType === 'userlist') return getSeconds(linesA, linesB, numRef, 'bed')
      return null
    }
    case 'count':
      // A gene count table is scored on its own; there is no dataset B.
      return getSeconds(linesA, 0, numRef, 'bed')
    default:
      return null
  }
}

/** Production's formatting: whole minutes under an hour, one decimal above. */
export function formatEstimate(seconds: number | null): string {
  if (seconds === null || !Number.isFinite(seconds)) return '—'
  const minutes = Math.round(seconds / 60)
  return minutes < 60 ? `${minutes} mins` : `${(minutes / 60).toFixed(1)} hr`
}

// /api/bed_sizes is a ~3,100-entry table that changes only when the database is
// rebuilt (the route sets max-age=3600). Production re-fetches it on every
// facet rebuild; fetching it once per page load is the same table with fewer
// requests. A failed fetch clears the cache so the next keystroke retries
// rather than leaving the panel stuck on an em dash for the whole session.
let bedSizesPromise: Promise<BedSizes> | null = null

function loadBedSizes(): Promise<BedSizes> {
  if (!bedSizesPromise) {
    bedSizesPromise = getBedSizes().catch((err) => {
      bedSizesPromise = null
      throw err
    })
  }
  return bedSizesPromise
}

async function refreshEstimate(facet: HTMLElement): Promise<void> {
  const out = document.getElementById('estimated-run-time')
  if (!out) return
  try {
    const sizes = await loadBedSizes()
    // Every input is read *after* the await, so overlapping calls all estimate
    // from the current form state and agree on the answer they write.
    const condition = FacetFilter.getCondition(facet)
    if (!condition) { out.textContent = '—'; return }
    out.textContent = formatEstimate(
      estimateSeconds({
        genome: condition.genome,
        aType: getCheckedValue('dataA-type'),
        bType: getCheckedValue('dataB-type'),
        dataAText: ($('dataA-text') as HTMLTextAreaElement).value,
        dataBText: ($('dataB-text') as HTMLTextAreaElement).value,
        permTime: getCheckedValue('dataB-perm'),
        numRef: sizes[bedSizeKey(condition)],
      }),
    )
  } catch (err) {
    console.error(err)
    out.textContent = '—'
  }
}

// ===== Job submission payload =====
// D7 (see docs/superpowers/plans/2026-09-18-post-parity-fixes.md, Task C1):
// no translation layer — this builds WABI's own field names directly, not
// this app's internal ones (track_class, dataA_type, ...). Kept as a pure
// function, separate from the DOM reads that feed it, specifically so a test
// can assert on the built object without letting a real submission reach
// WABI (routes/jobs.rb forwards `params` to WABI verbatim).
export interface EnrichmentFormState {
  aType: string
  bType: string
  dataAText: string
  dataBText: string
  title: string
  dataATitle: string
  dataBTitle: string
  permTime: string
  distanceUp: string
  distanceDown: string
}

export function buildEnrichmentParams(
  condition: Pick<FacetCondition, 'genome' | 'track_class' | 'cell_type_class' | 'qval'>,
  form: EnrichmentFormState,
): Record<string, unknown> {
  const params: Record<string, unknown> = {
    genome: condition.genome,
    antigenClass: condition.track_class,
    cellClass: condition.cell_type_class,
    threshold: qvalCodeToThreshold(condition.qval),
    typeA: form.aType,
    bedAFile: form.dataAText,
    typeB: form.bType,
    title: form.title,
    descriptionA: form.dataATitle,
    descriptionB: form.dataBTitle,
    // Restored per D8: production always submits these (default 5000),
    // even though the inputs are only shown in gene-list / gene-count-table
    // modes — see syncDatasetBVisibility's #distance-tss-row toggle.
    distanceUp: form.distanceUp,
    distanceDown: form.distanceDown,
  }
  if (form.bType === 'rnd') params.permTime = form.permTime
  // bedBFile is ALWAYS sent. Production's retrieveInputData() substitutes the
  // literal string "empty" for a blank textarea, and its own validation then
  // requires the field to be present unless typeA is "count" - so omitting it
  // for Random permutation (the default) made WABI reject every submission
  // from that path.
  params.bedBFile = orEmpty(form.dataBText)
  return params
}

/** Production sends the literal "empty" rather than an empty string. */
function orEmpty(text: string): string {
  return text.trim() === '' ? 'empty' : text
}

// ===== Try with example =====
async function loadExample(): Promise<void> {
  if (!currentGenome) return
  const status = $('submit-status')
  try {
    const res = await fetch(`/examples/${encodeURIComponent(currentGenome)}/bedA.txt`)
    if (!res.ok) throw new Error(`example fetch: ${res.status}`)
    const text = await res.text()
    ;(document.getElementById('dataA-bed') as HTMLInputElement).checked = true
    ;($('dataA-text') as HTMLTextAreaElement).value = text
    syncDatasetBVisibility()
    ;($('dataA-text') as HTMLTextAreaElement).dispatchEvent(new Event('input', { bubbles: true }))
  } catch (err) {
    console.error(err)
    status.textContent = 'Failed to load example data.'
  }
}

// Task D2: the FacetFilterOptions this page's genome-change handler passes
// to FacetFilter.init, pulled out into its own exported function rather than
// inlined there. Production's generateExperimentTypeOptions() explicitly
// drops "Annotation tracks" from Enrichment Analysis's experiment-type list
// (`if (label != "Annotation tracks")`); Peak Browser (see
// peakBrowserFacetFilterOptions in peak-browser.ts) passes no such
// exclusion, since annotation tracks are a legitimate track type there.
// Extracting this — instead of just commenting the inline object literal —
// is what lets enrichment-analysis.test.ts assert against the *actual*
// options this call site builds, so an edit that drops the exclusion here
// (or accidentally adds it in peak-browser.ts) fails the suite instead of
// only a live manual check.
export function enrichmentFacetFilterOptions(
  mount: Record<'track_class' | 'cell_type_class' | 'qval', HTMLElement>,
): FacetFilterOptions {
  return {
    render: 'listbox',
    mount,
    excludeTrackClassIds: ['Annotation tracks'],
  }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const status = $('submit-status')

  // Anchor element for FacetFilter's internal registry / facet-change event.
  // In list-box mode the five facets render into their own mount points
  // (below), so this container never enters the document.
  const facet = document.createElement('div')

  // Production's Enrichment Analysis exposes only experiment type, cell type
  // class and threshold - the subclass panels belong to the Peak Browser.
  const mount: Record<'track_class' | 'cell_type_class' | 'qval', HTMLElement> = {
    track_class:        $('facet-track-class'),
    cell_type_class:    $('facet-cell-type-class'),
    qval:               $('facet-qval'),
  }


  facet.addEventListener('facet-change', () => {
    void refreshEstimate(facet)
  })

  // Production rebinds "click keyup paste" over every input/select/textarea on
  // the page each time it recalculates. Two delegated listeners have the same
  // reach with none of the rebinding: 'input' catches typing and pasting into
  // the dataset textareas, 'change' catches the dataset A/B and permutation
  // radios (and the facet's own <select>s, whose authoritative refresh is the
  // facet-change above — this one just runs a beat earlier and agrees).
  document.addEventListener('input', () => { void refreshEstimate(facet) })
  document.addEventListener('change', () => { void refreshEstimate(facet) })

  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    currentGenome = detail.genome
    if (FacetFilter.getCondition(facet)) {
      await FacetFilter.setGenome(facet, detail.genome)
    } else {
      await FacetFilter.init(facet, detail.genome, enrichmentFacetFilterOptions(mount))
    }
    void refreshEstimate(facet)
  })

  GenomeTabs.init(tabs, data.genomes)
  initInfoPopovers(document, HELP_TEXT)

  // Pre-fill from POST body if present. syncDatasetBVisibility() below is
  // this app's positionGene(): it runs once, after these radios are set, and
  // takes care of the panel gating and the TSS distance range.
  const prefill = prefillSelection(data.prefill)
  if (prefill) {
    ;(document.getElementById(prefill.aType === 'gene' ? 'dataA-genes' : 'dataA-bed') as HTMLInputElement).checked = true
    ;(document.getElementById(`dataB-${prefill.bType}`) as HTMLInputElement).checked = true
    ;($('dataA-text') as HTMLTextAreaElement).value = prefill.aText
    ;($('dataB-text') as HTMLTextAreaElement).value = prefill.bText
  }

  document.querySelectorAll<HTMLInputElement>('input[name="dataA-type"], input[name="dataB-type"]').forEach((r) => {
    r.addEventListener('change', syncDatasetBVisibility)
  })
  syncDatasetBVisibility()

  readFileToTextarea(
    $('dataA-file') as HTMLInputElement,
    $('dataA-text') as HTMLTextAreaElement,
  )
  readFileToTextarea(
    $('dataB-file') as HTMLInputElement,
    $('dataB-text') as HTMLTextAreaElement,
  )

  $('try-example').addEventListener('click', (e) => {
    e.preventDefault()
    void loadExample()
  })

  void refreshEstimate(facet)

  $('submit-job').addEventListener('click', async () => {
    const condition = FacetFilter.getCondition(facet)
    if (!condition) { status.textContent = 'Filter not ready yet.'; return }

    const aType = getCheckedValue('dataA-type')
    const bType = getCheckedValue('dataB-type')
    const dataAText = ($('dataA-text') as HTMLTextAreaElement).value.trim()
    if (!dataAText) { status.textContent = 'Dataset A is empty.'; return }

    status.textContent = 'Submitting…'
    try {
      // buildEnrichmentParams (and qvalCodeToThreshold inside it) is called
      // inside this try, not before it: qvalCodeToThreshold throws on an
      // unparseable qval code rather than guessing, and that throw must
      // surface as a reported submit failure, not an unhandled promise
      // rejection that leaves the button silently inert.
      const params = buildEnrichmentParams(condition, {
        aType,
        bType,
        dataAText,
        dataBText: ($('dataB-text') as HTMLTextAreaElement).value,
        title: ($('title') as HTMLInputElement).value,
        dataATitle: ($('dataA-title') as HTMLInputElement).value,
        dataBTitle: ($('dataB-title') as HTMLInputElement).value,
        permTime: getCheckedValue('dataB-perm'),
        distanceUp: ($('distance-up') as HTMLInputElement).value,
        distanceDown: ($('distance-down') as HTMLInputElement).value,
      })

      const result = await submitJob({ type: 'enrichment_analysis', params })
      window.location.href = `/enrichment_analysis_result?id=${encodeURIComponent(result.job_id)}&backend=${encodeURIComponent(result.backend)}`
    } catch (err) {
      console.error(err)
      status.textContent = 'Submit failed. Try again or check the service status.'
    }
  })
}

// Guarded (rather than a bare top-level call) so buildEnrichmentParams and
// qvalCodeToThreshold can be imported and unit-tested under plain Node,
// which has no `document` — see enrichment-analysis.test.ts, and
// colo-result.ts / target-genes-result.ts for the same pattern.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
