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

type FacetKey = 'track_class' | 'track_subclass' | 'cell_type_class' | 'cell_type_subclass' | 'qval'

export interface FacetFilterOptions {
  render?: FacetRenderMode
  mount?: Record<string, HTMLElement>
}

// Abstracts over a single facet's control so the cascade logic below doesn't
// care whether it is backed by a plain <select> or a ListBox.
interface FacetControl {
  readonly value: string
  setLabeledItems(items: ClassificationItem[]): void
  setPlainValues(values: string[]): void
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

  setLabeledItems(items: ClassificationItem[]): void {
    const previous = this.select.value
    this.select.replaceChildren(...items.map((it) => {
      const opt = document.createElement('option')
      opt.value = it.id
      opt.textContent = labelWithCount(it)
      return opt
    }))
    if (items.some((it) => it.id === previous)) {
      this.select.value = previous
    }
  }

  setPlainValues(values: string[]): void {
    this.select.replaceChildren(...values.map((v) => {
      const opt = document.createElement('option')
      opt.value = v
      opt.textContent = v
      return opt
    }))
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

  setLabeledItems(items: ClassificationItem[]): void {
    const previous = this.box.value ?? undefined
    const selected = items.some((it) => it.id === previous) ? previous : undefined
    const options: ListBoxOption[] = items.map((it) => ({ id: it.id, label: it.label, count: it.count }))
    this.box.setOptions(options, selected)
  }

  setPlainValues(values: string[]): void {
    const previous = this.box.value ?? undefined
    const selected = previous != null && values.includes(previous) ? previous : undefined
    const options: ListBoxOption[] = values.map((v) => ({ id: v, label: v, count: null }))
    this.box.setOptions(options, selected)
  }

  onChange(handler: () => void): void {
    this.handler = handler
  }
}

function requireMount(mount: Record<string, HTMLElement>, key: FacetKey): HTMLElement {
  const el = mount[key]
  if (!el) throw new Error(`FacetFilter: missing mount point for "${key}"`)
  return el
}

async function loadTrackClasses(inst: Instance): Promise<void> {
  const cell = inst.cellTypeClass.value || undefined
  const items = await listTrackClasses(inst.genome, cell)
  inst.trackClass.setLabeledItems(items)
}

async function loadCellTypeClasses(inst: Instance): Promise<void> {
  const items = await listCellTypeClasses(inst.genome, inst.trackClass.value)
  inst.cellTypeClass.setLabeledItems(items)
}

async function loadTrackSubclasses(inst: Instance): Promise<void> {
  const items = await listTrackSubclasses(inst.genome, inst.trackClass.value, inst.cellTypeClass.value || undefined)
  inst.trackSubclass.setLabeledItems(items)
}

async function loadCellTypeSubclasses(inst: Instance): Promise<void> {
  const items = await listCellTypeSubclasses(inst.genome, inst.trackClass.value, inst.cellTypeClass.value || undefined)
  inst.cellTypeSubclass.setLabeledItems(items)
}

async function loadQvalRange(inst: Instance): Promise<void> {
  try {
    const values = await getQvalRange()
    inst.qval.setPlainValues(values)
  } catch (err) {
    console.warn('Failed to load qval range:', err)
  }
}

async function initialLoad(inst: Instance): Promise<void> {
  // Sequential: cell_type_classes requires a non-empty track_class, and the two
  // subclass facets need a *resolved* cell_type_class before they fetch — an
  // empty cell_type_class value is not treated as "any" server-side, it's
  // treated as "no cell type" and returns an empty result. On init all three
  // selects start empty, so track_class must seed first, then cell_type_class
  // must resolve, and only then can both subclass facets load (in parallel).
  await loadTrackClasses(inst)
  await loadCellTypeClasses(inst)
  await Promise.all([loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

async function reloadOnTrackChange(inst: Instance): Promise<void> {
  await Promise.all([loadCellTypeClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

async function reloadOnCellChange(inst: Instance): Promise<void> {
  await Promise.all([loadTrackClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

function attachHandlers(inst: Instance): void {
  inst.trackClass.onChange(async () => {
    // bidirectional: refresh cell types and both subclass lists
    await reloadOnTrackChange(inst)
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.cellTypeClass.onChange(async () => {
    await reloadOnCellChange(inst)
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.trackSubclass.onChange(() => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.cellTypeSubclass.onChange(() => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.qval.onChange(() => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
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
    trackSubclass: new ListBoxControl(requireMount(mount, 'track_subclass'), 'facet-track-subclass'),
    cellTypeSubclass: new ListBoxControl(requireMount(mount, 'cell_type_subclass'), 'facet-cell-type-subclass'),
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
    }
    registry.set(container, inst)

    attachHandlers(inst)

    await Promise.all([initialLoad(inst), loadQvalRange(inst)])
    container.dispatchEvent(new CustomEvent('facet-change'))
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
    await initialLoad(inst)
    container.dispatchEvent(new CustomEvent('facet-change'))
  },
}
