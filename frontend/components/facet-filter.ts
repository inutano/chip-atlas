// frontend/components/facet-filter.ts
// Cascading dropdowns with bidirectional count updates.
// genome → track_class ⇄ cell_type_class → track_subclass + cell_type_subclass → qval
//
// Supports two rendering modes:
//   - 'dropdown' (default): five labelled <select> elements appended to `container`,
//     exactly as before. All existing callers rely on this and must see no change.
//   - 'listbox': each facet renders as a ListBox (multi-row <select size="8">) into
//     the element supplied via `mount[facetKey]`, so a page can scatter the five
//     facets across separate panels. `container` is still used as the anchor for
//     the `facet-change` event and as the WeakMap registry key.

import {
  listTrackClasses,
  listCellTypeClasses,
  listTrackSubclasses,
  listCellTypeSubclasses,
  getQvalRange,
  type ClassificationItem,
} from '../api/client'
import { ListBox, type ListBoxOption } from './list-box'

export interface FacetCondition {
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  qval: string
}

export type FacetRenderMode = 'dropdown' | 'listbox'

// Production labels each qval option with -10*Log10(Q) ("05" -> "50"), matching
// the info-btn text ("If 50 is set here, peaks with Q value < 1E-05 are shown").
// The underlying option value stays the raw file-suffix string ("05") either way.
function qvalLabel(value: string): string {
  const n = parseInt(value, 10)
  return Number.isNaN(n) ? value : String(n * 10)
}

type QvalOption = { id: string; label: string }

// Production (old-app/public/js/pj/peak_browser.js:245-262) does not send the
// four /qvalue_range codes for these two track classes — the significance
// threshold does not apply to methylation calls or to annotation tracks, so
// it sends a single fixed "NA" option instead: value "bs" for Bisulfite-Seq,
// "anno" for Annotation tracks (both values matter: they are what
// bedfiles.qval actually contains for these rows, confirmed via the local
// API/sqlite — see docs/review-2026-09-23/findings/ui-peak-browser.md PB-18,
// PB-19). Every other track class keeps the real codes from /api/qval_range,
// labelled exactly as before.
export function qvalOptionsFor(trackClass: string, apiValues: string[]): QvalOption[] {
  if (trackClass === 'Bisulfite-Seq') return [{ id: 'bs', label: 'NA' }]
  if (trackClass === 'Annotation tracks') return [{ id: 'anno', label: 'NA' }]
  return apiValues.map((v) => ({ id: v, label: qvalLabel(v) }))
}

// The four track classes whose "Track type (optional)" (track_subclass) panel
// production hardcodes to a single "NA" row instead of calling the API
// (peak_browser.js:98-109). These are the API's own ids — check casing via
// `curl 'http://localhost:9292/api/track_classes?genome=hg38'` rather than
// production's display labels ("DNase-Seq"); "DNase-seq" (lower-case "seq")
// is what the id actually is.
export const NA_ONLY_TRACK_CLASSES: readonly string[] = ['Input control', 'ATAC-Seq', 'DNase-seq', 'Bisulfite-Seq']

// Pure filter/substitution step (PB-14, PB-19), mirroring qvalOptionsFor:
// kept separate from the async fetch in loadTrackSubclasses so it can be
// unit-tested without a DOM or network — see facet-filter.test.ts.
//
// NA_ONLY_TRACK_CLASSES classes: production never calls the API for these -
// loadTrackSubclasses skips the fetch entirely and this returns the fixed
// "NA" row regardless of what (if anything) is passed as apiItems.
// 'Annotation tracks': production does call the API but drops the "All"
// (id "-") entry so only real annotations are offered (peak_browser.js:127-
// 138); the existing "preserve selection, else first row" logic in
// DropdownControl/ListBoxControl then leaves the first annotation selected,
// same as production's `i == 1` special case (index 0 was "All").
// Everything else: apiItems unchanged.
export function trackSubclassItemsFor(trackClass: string, apiItems: ClassificationItem[]): ClassificationItem[] {
  if (NA_ONLY_TRACK_CLASSES.includes(trackClass)) {
    return [{ id: '-', label: 'NA', count: null }]
  }
  if (trackClass === 'Annotation tracks') {
    return apiItems.filter((it) => it.id !== '-')
  }
  return apiItems
}

export type FacetKey = 'track_class' | 'track_subclass' | 'cell_type_class' | 'cell_type_subclass' | 'qval'

export interface FacetFilterOptions {
  render?: FacetRenderMode
  mount?: Record<string, HTMLElement>
  // Task D2: Enrichment Analysis excludes "Annotation tracks" from its
  // experiment-type list (production's generateExperimentTypeOptions() does
  // this with an explicit `if (label != "Annotation tracks")`), while Peak
  // Browser keeps it — annotation tracks are a legitimate track type there.
  // Both pages share this one FacetFilter, so the exclusion is a per-call
  // option rather than baked into loadTrackClasses, and it filters the
  // track_class list only — cell/subclass facets are unaffected.
  excludeTrackClassIds?: string[]
}

// Abstracts over a single facet's control so the cascade logic below doesn't
// care whether it is backed by a plain <select> or a ListBox.
interface FacetControl {
  readonly value: string
  // Returns whether it fell back to selecting the first row because
  // `items` didn't offer the control's previous value (mirrors
  // ListBox.setOptions's own return value) — PB-11 uses this to notice when
  // a retained cell-type-class selection didn't survive a genome switch, so
  // it can refresh the track-class counts that were fetched with the
  // now-stale value.
  setLabeledItems(items: ClassificationItem[]): boolean
  setQvalOptions(options: QvalOption[]): void
  onChange(handler: () => void): void
}

interface Instance {
  container: HTMLElement
  genome: string
  trackClass: FacetControl
  cellTypeClass: FacetControl
  trackSubclass: FacetControl
  cellTypeSubclass: FacetControl
  qval: FacetControl
  excludeTrackClassIds: string[]
  // Cached /api/qval_range codes, fetched once by loadQvalRange. null until
  // that first load resolves; renderQval no-ops until then rather than
  // rendering an empty list from a not-yet-populated cache.
  qvalApiValues: string[] | null
}

const registry = new WeakMap<HTMLElement, Instance>()

function labelWithCount(item: ClassificationItem): string {
  return item.count == null ? item.label : `${item.label} (n=${item.count.toLocaleString()})`
}

function makeLabeledSelect(id: string, labelText: string): { wrap: HTMLDivElement; select: HTMLSelectElement } {
  const wrap = document.createElement('div')
  wrap.className = 'mb-2'

  const label = document.createElement('label')
  label.htmlFor = id
  label.className = 'form-label small text-muted mb-1'
  label.textContent = labelText

  const select = document.createElement('select')
  select.id = id
  select.className = 'form-select form-select-sm'

  wrap.appendChild(label)
  wrap.appendChild(select)
  return { wrap, select }
}

class DropdownControl implements FacetControl {
  constructor(private select: HTMLSelectElement) {}

  get value(): string {
    return this.select.value
  }

  setLabeledItems(items: ClassificationItem[]): boolean {
    const previous = this.select.value
    this.select.replaceChildren(...items.map((it) => {
      const opt = document.createElement('option')
      opt.value = it.id
      opt.textContent = labelWithCount(it)
      return opt
    }))
    const matched = items.some((it) => it.id === previous)
    if (matched) {
      this.select.value = previous
    }
    // A plain <select> auto-selects its first <option> when none carries
    // `selected` explicitly — so when nothing matched, the browser has
    // already fallen back to the first row (if there is one), mirroring
    // ListBox.setOptions's own fallback below.
    return !matched && items.length > 0
  }

  setQvalOptions(options: QvalOption[]): void {
    const previous = this.select.value
    this.select.replaceChildren(...options.map((opt) => {
      const el = document.createElement('option')
      el.value = opt.id
      el.textContent = opt.label
      return el
    }))
    if (options.some((opt) => opt.id === previous)) {
      this.select.value = previous
    }
  }

  onChange(handler: () => void): void {
    this.select.addEventListener('change', handler)
  }
}

class ListBoxControl implements FacetControl {
  private box: ListBox
  private handler?: () => void

  constructor(container: HTMLElement, id: string) {
    this.box = new ListBox({
      container,
      id,
      options: [],
      onChange: () => this.handler?.(),
    })
  }

  get value(): string {
    return this.box.value ?? ''
  }

  setLabeledItems(items: ClassificationItem[]): boolean {
    const previous = this.box.value ?? undefined
    const selected = items.some((it) => it.id === previous) ? previous : undefined
    const options: ListBoxOption[] = items.map((it) => ({ id: it.id, label: it.label, count: it.count }))
    return this.box.setOptions(options, selected)
  }

  setQvalOptions(options: QvalOption[]): void {
    const previous = this.box.value ?? undefined
    const selected = options.some((opt) => opt.id === previous) ? previous : undefined
    const boxOptions: ListBoxOption[] = options.map((opt) => ({ id: opt.id, label: opt.label, count: null }))
    this.box.setOptions(boxOptions, selected)
  }

  onChange(handler: () => void): void {
    this.handler = handler
  }
}

// A page that has no control for a facet (Enrichment Analysis has no track/cell
// subclass panels, matching production) gets this stand-in. '-' is the API's
// "All" sentinel, so an omitted facet simply does not narrow the query.
class AbsentControl implements FacetControl {
  get value(): string { return '-' }
  setLabeledItems(_items: ClassificationItem[]): boolean { return false }
  setQvalOptions(_options: QvalOption[]): void { /* nothing to render */ }
  onChange(_handler: () => void): void { /* never fires */ }
}

function requireMount(mount: Record<string, HTMLElement>, key: FacetKey): HTMLElement {
  const el = mount[key]
  if (!el) throw new Error(`FacetFilter: missing mount point for "${key}"`)
  return el
}

// Pure filter step (Task D2), kept separate from the async fetch in
// loadTrackClasses so it can be unit-tested without a DOM or network —
// see facet-filter.test.ts.
//
// Filters on `it.id`, not `it.label`, even though production's own rule is
// written against the label (`if (label != "Annotation tracks")`). This is
// deliberate, not an oversight: EXPERIMENT_TYPES gives "Annotation tracks"
// the same string for both id and label today, so the two reads agree. If
// they ever diverge, callers pass ids (see enrichmentFacetFilterOptions in
// enrichment-analysis.ts), so this must keep matching on id — don't "fix"
// this to match on label instead.
export function excludeTrackClasses(items: ClassificationItem[], excludeIds: string[]): ClassificationItem[] {
  return excludeIds.length === 0 ? items : items.filter((it) => !excludeIds.includes(it.id))
}

// Re-renders the qval facet from the cached /api/qval_range codes for the
// currently-resolved track class. A no-op until loadQvalRange's first fetch
// populates the cache (init kicks that fetch off in parallel with the rest
// of the cascade — see FacetFilter.init — so it may not have landed yet the
// first time a track class resolves; loadQvalRange renders once it does).
function renderQval(inst: Instance): void {
  if (inst.qvalApiValues === null) return
  inst.qval.setQvalOptions(qvalOptionsFor(inst.trackClass.value, inst.qvalApiValues))
}

async function loadTrackClasses(inst: Instance): Promise<void> {
  const cell = inst.cellTypeClass.value || undefined
  const items = await listTrackClasses(inst.genome, cell)
  inst.trackClass.setLabeledItems(excludeTrackClasses(items, inst.excludeTrackClassIds))
  // The qval list depends only on which track class is now selected, so
  // every place a track class resolves (user change, cell-type-class change,
  // genome switch) must re-render it — see qvalOptionsFor.
  renderQval(inst)
}

// Returns whether cell_type_class fell back to its first row because the
// instance's previous value wasn't offered for this genome/track_class -
// see FacetFilter.setGenome (PB-11).
async function loadCellTypeClasses(inst: Instance): Promise<boolean> {
  const items = await listCellTypeClasses(inst.genome, inst.trackClass.value)
  return inst.cellTypeClass.setLabeledItems(items)
}

async function loadTrackSubclasses(inst: Instance): Promise<void> {
  const trackClass = inst.trackClass.value
  // PB-14: production never calls the API for these four classes.
  const apiItems = NA_ONLY_TRACK_CLASSES.includes(trackClass)
    ? []
    : await listTrackSubclasses(inst.genome, trackClass, inst.cellTypeClass.value || undefined)
  inst.trackSubclass.setLabeledItems(trackSubclassItemsFor(trackClass, apiItems))
}

async function loadCellTypeSubclasses(inst: Instance): Promise<void> {
  const items = await listCellTypeSubclasses(inst.genome, inst.trackClass.value, inst.cellTypeClass.value || undefined)
  inst.cellTypeSubclass.setLabeledItems(items)
}

async function loadQvalRange(inst: Instance): Promise<void> {
  try {
    inst.qvalApiValues = await getQvalRange()
  } catch (err) {
    console.warn('Failed to load qval range:', err)
    return
  }
  renderQval(inst)
}

// Returns whether cell_type_class fell back to its first row (see
// loadCellTypeClasses) — only FacetFilter.setGenome acts on this; FacetFilter.
// init discards it, since on a fresh instance every facet starts empty and
// "falling back" there is the normal seeding behaviour, not a PB-11 staleness
// signal.
async function initialLoad(inst: Instance): Promise<boolean> {
  // Sequential: cell_type_classes requires a non-empty track_class, and the two
  // subclass facets need a *resolved* cell_type_class before they fetch — an
  // empty cell_type_class value is not treated as "any" server-side, it's
  // treated as "no cell type" and returns an empty result. On init all three
  // selects start empty, so track_class must seed first, then cell_type_class
  // must resolve, and only then can both subclass facets load (in parallel).
  await loadTrackClasses(inst)
  const cellTypeClassFellBack = await loadCellTypeClasses(inst)
  await Promise.all([loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
  return cellTypeClassFellBack
}

async function reloadOnTrackChange(inst: Instance): Promise<void> {
  // Sequential: both subclass facets read cell_type_class.value, so it must
  // finish resolving (and may itself fall back to a different value under the
  // new track class) before either subclass fetch reads it (PB-11 — a
  // Promise.all here would race the subclass fetches against a
  // cell_type_class that has not resolved for the new track class yet).
  await loadCellTypeClasses(inst)
  await Promise.all([loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
  // The user just picked a new track_class directly (that's what triggered
  // this reload) — unlike the other reload paths, nothing above calls
  // loadTrackClasses, so this is the one place that must re-render qval
  // itself for the newly-picked class.
  renderQval(inst)
}

async function reloadOnCellChange(inst: Instance): Promise<void> {
  // Sequential for the same reason as reloadOnTrackChange, mirrored: both
  // subclass facets also read track_class.value, so loadTrackClasses (which
  // can change it) must resolve first.
  await loadTrackClasses(inst)
  await Promise.all([loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

// Every 'facet-change' dispatch site funnels through here so the event
// always carries which facet just settled — pages (Task 3) use this to tell
// which side of a paired change (e.g. antigen vs. cell type) the user
// actually touched. Existing listeners take no argument and so ignore
// `detail` entirely; adding it is not a behaviour change for them.
function dispatchFacetChange(inst: Instance, facet: FacetKey | 'init'): void {
  inst.container.dispatchEvent(new CustomEvent('facet-change', { detail: { facet } }))
}

function attachHandlers(inst: Instance): void {
  inst.trackClass.onChange(async () => {
    // bidirectional: refresh cell types and both subclass lists
    await reloadOnTrackChange(inst)
    dispatchFacetChange(inst, 'track_class')
  })
  inst.cellTypeClass.onChange(async () => {
    await reloadOnCellChange(inst)
    dispatchFacetChange(inst, 'cell_type_class')
  })
  inst.trackSubclass.onChange(() => {
    dispatchFacetChange(inst, 'track_subclass')
  })
  inst.cellTypeSubclass.onChange(() => {
    dispatchFacetChange(inst, 'cell_type_subclass')
  })
  inst.qval.onChange(() => {
    dispatchFacetChange(inst, 'qval')
  })
}

function buildDropdownControls(container: HTMLElement): {
  trackClass: FacetControl
  cellTypeClass: FacetControl
  trackSubclass: FacetControl
  cellTypeSubclass: FacetControl
  qval: FacetControl
} {
  const trackClass = makeLabeledSelect('facet-track-class', 'Track type class')
  const cellTypeClass = makeLabeledSelect('facet-cell-type-class', 'Cell type class')
  const trackSubclass = makeLabeledSelect('facet-track-subclass', 'Track type')
  const cellTypeSubclass = makeLabeledSelect('facet-cell-type-subclass', 'Cell type')
  const qval = makeLabeledSelect('facet-qval', 'Threshold (qval)')

  container.replaceChildren(
    trackClass.wrap, cellTypeClass.wrap, trackSubclass.wrap, cellTypeSubclass.wrap, qval.wrap,
  )

  return {
    trackClass: new DropdownControl(trackClass.select),
    cellTypeClass: new DropdownControl(cellTypeClass.select),
    trackSubclass: new DropdownControl(trackSubclass.select),
    cellTypeSubclass: new DropdownControl(cellTypeSubclass.select),
    qval: new DropdownControl(qval.select),
  }
}

function buildListBoxControls(mount: Record<string, HTMLElement>): {
  trackClass: FacetControl
  cellTypeClass: FacetControl
  trackSubclass: FacetControl
  cellTypeSubclass: FacetControl
  qval: FacetControl
} {
  return {
    trackClass: new ListBoxControl(requireMount(mount, 'track_class'), 'facet-track-class'),
    cellTypeClass: new ListBoxControl(requireMount(mount, 'cell_type_class'), 'facet-cell-type-class'),
    trackSubclass: mount.track_subclass
      ? new ListBoxControl(mount.track_subclass, 'facet-track-subclass')
      : new AbsentControl(),
    cellTypeSubclass: mount.cell_type_subclass
      ? new ListBoxControl(mount.cell_type_subclass, 'facet-cell-type-subclass')
      : new AbsentControl(),
    qval: new ListBoxControl(requireMount(mount, 'qval'), 'facet-qval'),
  }
}

export const FacetFilter = {
  async init(container: HTMLElement, genome: string, options: FacetFilterOptions = {}): Promise<void> {
    const render = options.render ?? 'dropdown'

    const controls = render === 'listbox'
      ? buildListBoxControls(options.mount ?? {})
      : buildDropdownControls(container)

    if (render === 'listbox') {
      // Facets render into their own mount points; the container itself stays empty.
      container.replaceChildren()
    }

    const inst: Instance = {
      container,
      genome,
      trackClass: controls.trackClass,
      cellTypeClass: controls.cellTypeClass,
      trackSubclass: controls.trackSubclass,
      cellTypeSubclass: controls.cellTypeSubclass,
      qval: controls.qval,
      excludeTrackClassIds: options.excludeTrackClassIds ?? [],
      qvalApiValues: null,
    }
    registry.set(container, inst)

    attachHandlers(inst)

    await Promise.all([initialLoad(inst), loadQvalRange(inst)])
    dispatchFacetChange(inst, 'init')
  },

  getCondition(container: HTMLElement): FacetCondition | null {
    const inst = registry.get(container)
    if (!inst) return null
    return {
      genome: inst.genome,
      track_class: inst.trackClass.value,
      track_subclass: inst.trackSubclass.value,
      cell_type_class: inst.cellTypeClass.value,
      cell_type_subclass: inst.cellTypeSubclass.value,
      qval: inst.qval.value,
    }
  },

  async setGenome(container: HTMLElement, genome: string): Promise<void> {
    const inst = registry.get(container)
    if (!inst) return
    inst.genome = genome
    const cellTypeClassFellBack = await initialLoad(inst)
    // PB-11: cell_type_class didn't offer the value retained from the old
    // genome, so loadTrackClasses's earlier call (the first step of
    // initialLoad, run before cell_type_class had resolved for this genome)
    // fetched track-class counts filtered by a value that no longer applies.
    // Now that cell_type_class has resolved to a real value for this genome,
    // redo it so the displayed counts match.
    if (cellTypeClassFellBack) {
      await loadTrackClasses(inst)
    }
    dispatchFacetChange(inst, 'init')
  },
}
