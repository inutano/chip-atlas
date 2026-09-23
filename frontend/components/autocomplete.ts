// frontend/components/autocomplete.ts
// Text input with substring-matching dropdown suggestions.
// Keyboard navigation: ArrowDown, ArrowUp, Enter, Escape.
// Optionally paired with a ListBox (a visible <select size="8">) that mirrors
// the same filtered set, restoring the old Flexselect "browse below the
// input" affordance. The paired list is fully optional and off by default.

import { ListBox, type ListBoxOption } from './list-box'

export interface AutocompleteOptions {
  pairedList?: HTMLElement
}

interface Instance {
  input: HTMLInputElement
  menu: HTMLUListElement
  items: string[]
  filtered: string[]
  active: number
  onSelect: (value: string) => void
  listBox?: ListBox
}

const MAX_RESULTS = 50
const registry = new WeakMap<HTMLInputElement, Instance>()
let listBoxSeq = 0

function toOptions(items: string[]): ListBoxOption[] {
  return items.map((value) => ({ id: value, label: value, count: null }))
}

function buildMenu(): HTMLUListElement {
  const menu = document.createElement('ul')
  menu.className = 'list-group autocomplete-menu'
  menu.setAttribute('role', 'listbox')
  menu.style.display = 'none'
  return menu
}

function placeMenu(input: HTMLInputElement, menu: HTMLUListElement): void {
  const parent = input.parentElement
  if (!parent) return
  if (getComputedStyle(parent).position === 'static') parent.style.position = 'relative'
  if (menu.parentElement !== parent) parent.appendChild(menu)

  menu.style.position = 'absolute'
  menu.style.top = `${input.offsetTop + input.offsetHeight}px`
  menu.style.left = `${input.offsetLeft}px`
  menu.style.width = `${input.offsetWidth}px`
  menu.style.zIndex = '1050'
  menu.style.maxHeight = '320px'
  menu.style.overflowY = 'auto'
}

function filter(items: string[], query: string): string[] {
  const q = query.trim().toLowerCase()
  if (!q) return items.slice(0, MAX_RESULTS)
  const out: string[] = []
  for (const item of items) {
    if (item.toLowerCase().includes(q)) {
      out.push(item)
      if (out.length >= MAX_RESULTS) break
    }
  }
  return out
}

// Unlike filter(), never caps an empty query: this feeds the paired list box
// (a browsable <select size="8">, not a dropdown), which production shows in
// full and which must not silently shrink to MAX_RESULTS the moment the
// input receives focus. A non-empty query still caps, matching the dropdown.
function filterForPairedList(items: string[], query: string): string[] {
  const q = query.trim().toLowerCase()
  if (!q) return items
  return filter(items, query)
}

// The item whose lower-cased, trimmed form equals the lower-cased, trimmed
// text, or null. Case-insensitive/trimmed equivalent of production's
// `$.inArray(input, options) > -1` (colo.js:153, target_genes.js:154), used
// to sync the paired ListBox to text the user typed without picking a
// suggestion.
export function exactMatch(items: string[], text: string): string | null {
  const q = text.trim().toLowerCase()
  if (!q) return null
  for (const item of items) {
    if (item.trim().toLowerCase() === q) return item
  }
  return null
}

// After the paired ListBox (re)populates, ListBox.setOptions — absent a
// `selected` it can match, which Autocomplete never passes — always lands on
// row one (list-box.ts), the same way production's appendOptions always gave
// the first <option> selected="selected" outright (colo.js:107-125,
// target_genes.js:113-120). Nothing fired onChange for that, so the page's
// own state (currentPrimary, currentTrack, ...) does not know about it yet.
// Tell it, the same way a user's own click would — but only when the input
// agrees with that row, so a value the user is still typing (not yet an
// exact match) is not silently overridden by whatever now sits on top.
function syncListBoxSelection(inst: Instance): void {
  const { listBox, input, items, onSelect } = inst
  if (!listBox) return
  const value = listBox.value
  if (value == null) return
  if (input.value === '' || exactMatch(items, input.value) === value) {
    onSelect(value)
  }
}

function render(inst: Instance): void {
  const { menu, filtered, active } = inst
  if (filtered.length === 0) {
    menu.style.display = 'none'
    menu.replaceChildren()
    inst.input.removeAttribute('aria-activedescendant')
    return
  }
  const inputId = inst.input.id || ''
  const optionId = (i: number) => `${inputId || 'ac'}-opt-${i}`
  menu.replaceChildren(...filtered.map((value, i) => {
    const li = document.createElement('li')
    li.id = optionId(i)
    li.className = 'list-group-item list-group-item-action' + (i === active ? ' active' : '')
    li.setAttribute('role', 'option')
    li.setAttribute('aria-selected', i === active ? 'true' : 'false')
    li.dataset.index = String(i)
    li.style.cursor = 'pointer'
    li.textContent = value
    li.addEventListener('mousedown', (e) => {
      e.preventDefault()
      select(inst, i)
    })
    return li
  }))
  if (active >= 0) {
    inst.input.setAttribute('aria-activedescendant', optionId(active))
  } else {
    inst.input.removeAttribute('aria-activedescendant')
  }
  menu.style.display = 'block'
  placeMenu(inst.input, menu)
}

function select(inst: Instance, index: number): void {
  const value = inst.filtered[index]
  if (value == null) return
  inst.input.value = value
  inst.onSelect(value)
  close(inst)
}

function open(inst: Instance): void {
  inst.filtered = filter(inst.items, inst.input.value)
  inst.active = inst.filtered.length > 0 ? 0 : -1
  render(inst)
  if (inst.listBox) inst.listBox.setOptions(toOptions(filterForPairedList(inst.items, inst.input.value)))
}

function close(inst: Instance): void {
  inst.filtered = []
  inst.active = -1
  inst.menu.style.display = 'none'
}

function move(inst: Instance, delta: number): void {
  if (inst.filtered.length === 0) return
  inst.active = (inst.active + delta + inst.filtered.length) % inst.filtered.length
  render(inst)
}

function attachKeyboard(inst: Instance): void {
  inst.input.addEventListener('keydown', (e) => {
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault()
        if (inst.menu.style.display === 'none') open(inst)
        else move(inst, 1)
        break
      case 'ArrowUp':
        e.preventDefault()
        move(inst, -1)
        break
      case 'Enter':
        if (inst.active >= 0) {
          e.preventDefault()
          select(inst, inst.active)
        }
        break
      case 'Escape':
        close(inst)
        break
    }
  })
}

export const Autocomplete = {
  init(input: HTMLInputElement, items: string[], onSelect: (value: string) => void, opts?: AutocompleteOptions): void {
    const menu = buildMenu()
    const inst: Instance = { input, menu, items, filtered: [], active: -1, onSelect }
    registry.set(input, inst)

    input.setAttribute('autocomplete', 'off')
    input.setAttribute('role', 'combobox')
    input.setAttribute('aria-autocomplete', 'list')

    if (opts?.pairedList) {
      // A real <select>: keyboard-accessible on its own. Do not layer
      // aria-activedescendant (that belongs to the dropdown menu only).
      const id = input.id ? `${input.id}-list-box` : `autocomplete-list-box-${++listBoxSeq}`
      inst.listBox = new ListBox({
        container: opts.pairedList,
        id,
        options: toOptions(items),
        onChange: (value) => {
          input.value = value
          onSelect(value)
          close(inst)
        },
      })
      syncListBoxSelection(inst)
    }

    input.addEventListener('focus', () => open(inst))
    input.addEventListener('input', () => open(inst))
    // Production's typeahead:select/keyup handler kept the <select> in sync
    // with whatever the input named exactly, even without Enter or a
    // suggestion click (colo.js:151-159, target_genes.js:152-157). This must
    // run after the open() listener above: open() repopulates the paired
    // list box to the filtered set (and, absent a match, re-lands it on that
    // set's first row) on every keystroke, which would otherwise clobber the
    // forced selection made here.
    input.addEventListener('input', () => {
      const m = exactMatch(inst.items, input.value)
      if (m && inst.listBox) {
        inst.listBox.value = m
        onSelect(m)
      }
    })
    input.addEventListener('blur', () => {
      // Delay close so a click on the menu can fire first.
      setTimeout(() => close(inst), 100)
    })

    attachKeyboard(inst)
  },

  setItems(input: HTMLInputElement, items: string[]): void {
    const inst = registry.get(input)
    if (!inst) return
    inst.items = items
    if (inst.listBox) {
      inst.listBox.setOptions(toOptions(items))
      syncListBoxSelection(inst)
    }
    if (document.activeElement === input) open(inst)
  },
}
