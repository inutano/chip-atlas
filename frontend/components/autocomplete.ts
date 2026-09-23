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
  // The last value handed to onSelect, so a later re-render (a keystroke's
  // filtered set, a fresh Autocomplete.setItems list) can tell a value it
  // already told the page about from a brand new auto-selection. Not the
  // same thing as the paired ListBox's own `.value`: that reflects whatever
  // is merely highlighted right now, including a row nothing has approved
  // yet (see resolvePairedSelection).
  selected: string | null
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

// The paired ListBox's selection after a keystroke, as one decision instead
// of two competing ones (2026-09-24 review, COLO-04/TG-09 follow-up).
// Before this, open() repopulated the box with the filtered set on every
// keystroke and let ListBox.setOptions auto-select its first row — with no
// `selected` to match, since Autocomplete never passed one — while a
// separate `input` listener forced the box to an exact text match. Neither
// told the page about the other's outcome in any defined order: typing "sta"
// visibly highlighted STAG1 while the page's own state still held the very
// first antigen loaded at page load, so "View" navigated with the wrong
// track.
//
// `items` is whatever set is actually on screen (the paired list's filtered
// options — see filterForPairedList — not the full unfiltered item list): an
// exact match is always a member of it, since filtering is substring
// inclusion and a string always contains itself, and "still among the
// filtered items" only means something for the set currently shown.
export function resolvePairedSelection(
  items: string[],
  query: string,
  current: string | null,
): { selected: string | null; changed: boolean } {
  const exact = exactMatch(items, query)
  const selected = exact ?? (current !== null && items.includes(current) ? current : (items[0] ?? null))
  return { selected, changed: selected !== current }
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
  inst.selected = value
  if (inst.listBox) inst.listBox.value = value
  inst.onSelect(value)
  close(inst)
}

function open(inst: Instance): void {
  inst.filtered = filter(inst.items, inst.input.value)
  inst.active = inst.filtered.length > 0 ? 0 : -1
  render(inst)
  if (inst.listBox) {
    const pairedItems = filterForPairedList(inst.items, inst.input.value)
    const { selected, changed } = resolvePairedSelection(pairedItems, inst.input.value, inst.selected)
    inst.listBox.setOptions(toOptions(pairedItems), selected ?? undefined)
    if (changed) {
      inst.selected = selected
      if (selected != null) inst.onSelect(selected)
    }
  }
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
    const inst: Instance = { input, menu, items, filtered: [], active: -1, onSelect, selected: null }
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
          inst.selected = value
          onSelect(value)
          close(inst)
        },
      })
      // `items` is always [] for every caller in this codebase (colo.ts,
      // target-genes.ts) — nothing to select yet. The Autocomplete.setItems
      // call every page makes right after init does the real sync, boolean
      // return and all (see below).
    }

    input.addEventListener('focus', () => open(inst))
    // 2026-09-24 review: this used to be two separate `input` listeners —
    // this one (filtering, and repopulating the paired list box) and a
    // second one forcing the box to an exact text match — with no defined
    // order between them. open() now resolves the paired box's selection
    // itself (exact match first: see resolvePairedSelection), so one
    // listener is enough and "exact match wins" is guaranteed by that
    // function's own branch order rather than by listener registration order.
    input.addEventListener('input', () => open(inst))
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
      // Prefer the page's last approved selection over whatever the box
      // happens to be showing, same as open(); consume the boolean Task 1
      // added so a genuinely new list (e.g. a different genome's antigens,
      // no longer containing it) tells the page about the row it lands on
      // instead of leaving that only on screen.
      const autoSelected = inst.listBox.setOptions(toOptions(items), inst.selected ?? undefined)
      if (autoSelected) {
        const value = inst.listBox.value
        if (value != null) {
          inst.selected = value
          inst.onSelect(value)
        }
      }
    }
    if (document.activeElement === input) open(inst)
  },
}
