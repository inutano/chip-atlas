// frontend/components/facet-filter.ts
// Cascading dropdowns with bidirectional count updates.
// genome → track_class ⇄ cell_type_class → track_subclass + cell_type_subclass → qval

import {
  listTrackClasses,
  listCellTypeClasses,
  listTrackSubclasses,
  listCellTypeSubclasses,
  getQvalRange,
  type ClassificationItem,
} from '../api/client'

export interface FacetCondition {
  genome: string
  track_class: string
  track_subclass: string
  cell_type_class: string
  cell_type_subclass: string
  qval: string
}

interface Instance {
  container: HTMLElement
  genome: string
  trackClass: HTMLSelectElement
  cellTypeClass: HTMLSelectElement
  trackSubclass: HTMLSelectElement
  cellTypeSubclass: HTMLSelectElement
  qval: HTMLSelectElement
}

const registry = new WeakMap<HTMLElement, Instance>()

function labelWithCount(item: ClassificationItem): string {
  return item.count == null ? item.label : `${item.label} (n=${item.count.toLocaleString()})`
}

function fillSelect(select: HTMLSelectElement, items: ClassificationItem[]): void {
  const previous = select.value
  select.replaceChildren(...items.map((it) => {
    const opt = document.createElement('option')
    opt.value = it.id
    opt.textContent = labelWithCount(it)
    return opt
  }))
  if (items.some((it) => it.id === previous)) {
    select.value = previous
  }
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

async function loadTrackClasses(inst: Instance): Promise<void> {
  const cell = inst.cellTypeClass.value || undefined
  const items = await listTrackClasses(inst.genome, cell)
  fillSelect(inst.trackClass, items)
}

async function loadCellTypeClasses(inst: Instance): Promise<void> {
  const items = await listCellTypeClasses(inst.genome, inst.trackClass.value)
  fillSelect(inst.cellTypeClass, items)
}

async function loadTrackSubclasses(inst: Instance): Promise<void> {
  const items = await listTrackSubclasses(inst.genome, inst.trackClass.value, inst.cellTypeClass.value || undefined)
  fillSelect(inst.trackSubclass, items)
}

async function loadCellTypeSubclasses(inst: Instance): Promise<void> {
  const items = await listCellTypeSubclasses(inst.genome, inst.trackClass.value, inst.cellTypeClass.value || undefined)
  fillSelect(inst.cellTypeSubclass, items)
}

async function loadQvalRange(inst: Instance): Promise<void> {
  try {
    const values = await getQvalRange()
    inst.qval.replaceChildren(...values.map((v) => {
      const opt = document.createElement('option')
      opt.value = v
      opt.textContent = v
      return opt
    }))
  } catch (err) {
    console.warn('Failed to load qval range:', err)
  }
}

async function initialLoad(inst: Instance): Promise<void> {
  // Sequential: cell_type_classes requires a non-empty track_class. On init both
  // selects start empty, so we must seed track_class first, then load the rest.
  await loadTrackClasses(inst)
  await Promise.all([loadCellTypeClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

async function reloadOnTrackChange(inst: Instance): Promise<void> {
  await Promise.all([loadCellTypeClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

async function reloadOnCellChange(inst: Instance): Promise<void> {
  await Promise.all([loadTrackClasses(inst), loadTrackSubclasses(inst), loadCellTypeSubclasses(inst)])
}

function attachHandlers(inst: Instance): void {
  inst.trackClass.addEventListener('change', async () => {
    // bidirectional: refresh cell types and both subclass lists
    await reloadOnTrackChange(inst)
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.cellTypeClass.addEventListener('change', async () => {
    await reloadOnCellChange(inst)
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.trackSubclass.addEventListener('change', () => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.cellTypeSubclass.addEventListener('change', () => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
  inst.qval.addEventListener('change', () => {
    inst.container.dispatchEvent(new CustomEvent('facet-change'))
  })
}

export const FacetFilter = {
  async init(container: HTMLElement, genome: string): Promise<void> {
    const trackClass = makeLabeledSelect('facet-track-class', 'Track type class')
    const cellTypeClass = makeLabeledSelect('facet-cell-type-class', 'Cell type class')
    const trackSubclass = makeLabeledSelect('facet-track-subclass', 'Track type')
    const cellTypeSubclass = makeLabeledSelect('facet-cell-type-subclass', 'Cell type')
    const qval = makeLabeledSelect('facet-qval', 'Threshold (qval)')

    container.replaceChildren(
      trackClass.wrap, cellTypeClass.wrap, trackSubclass.wrap, cellTypeSubclass.wrap, qval.wrap,
    )

    const inst: Instance = {
      container,
      genome,
      trackClass: trackClass.select,
      cellTypeClass: cellTypeClass.select,
      trackSubclass: trackSubclass.select,
      cellTypeSubclass: cellTypeSubclass.select,
      qval: qval.select,
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
