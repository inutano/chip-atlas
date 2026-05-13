// frontend/components/autocomplete.ts
// Text input with substring-matching dropdown suggestions.
// Keyboard navigation: ArrowDown, ArrowUp, Enter, Escape.

interface Instance {
  input: HTMLInputElement
  menu: HTMLUListElement
  items: string[]
  filtered: string[]
  active: number
  onSelect: (value: string) => void
}

const MAX_RESULTS = 50
const registry = new WeakMap<HTMLInputElement, Instance>()

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

function render(inst: Instance): void {
  const { menu, filtered, active } = inst
  if (filtered.length === 0) {
    menu.style.display = 'none'
    menu.replaceChildren()
    return
  }
  menu.replaceChildren(...filtered.map((value, i) => {
    const li = document.createElement('li')
    li.className = 'list-group-item list-group-item-action' + (i === active ? ' active' : '')
    li.setAttribute('role', 'option')
    li.dataset.index = String(i)
    li.style.cursor = 'pointer'
    li.textContent = value
    li.addEventListener('mousedown', (e) => {
      e.preventDefault()
      select(inst, i)
    })
    return li
  }))
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
  init(input: HTMLInputElement, items: string[], onSelect: (value: string) => void): void {
    const menu = buildMenu()
    const inst: Instance = { input, menu, items, filtered: [], active: -1, onSelect }
    registry.set(input, inst)

    input.setAttribute('autocomplete', 'off')
    input.setAttribute('role', 'combobox')
    input.setAttribute('aria-autocomplete', 'list')

    input.addEventListener('focus', () => open(inst))
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
    if (document.activeElement === input) open(inst)
  },
}
