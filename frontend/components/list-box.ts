// frontend/components/list-box.ts
// Bootstrap 3 style multi-row list box: a <select size="8"> with counts.
// Replaces the old Flexselect control.

export interface ListBoxOption {
  id: string
  label: string
  count?: number | null
}

export interface ListBoxOptions {
  container: HTMLElement
  id: string
  size?: number
  options: ListBoxOption[]
  selected?: string
  onChange?: (id: string) => void
}

export class ListBox {
  private select: HTMLSelectElement
  private onChange?: (id: string) => void

  constructor(opts: ListBoxOptions) {
    this.onChange = opts.onChange

    // Suffix the id: callers (e.g. FacetFilter's list-box mode) commonly pass
    // the same id as the mount <div> itself, which produced two elements
    // sharing one id - invalid HTML, and getElementById(id) silently
    // returned the div instead of this <select>.
    const select = document.createElement('select')
    select.className = 'form-control list-box'
    select.id = `${opts.id}-select`
    select.size = opts.size ?? 8
    select.addEventListener('change', () => {
      if (this.onChange && select.value) this.onChange(select.value)
    })

    opts.container.innerHTML = ''
    opts.container.appendChild(select)
    this.select = select

    this.setOptions(opts.options, opts.selected)
  }

  setOptions(options: ListBoxOption[], selected?: string): void {
    this.select.innerHTML = ''
    let matched = false
    for (const opt of options) {
      const el = document.createElement('option')
      el.value = opt.id
      el.textContent =
        opt.count === null || opt.count === undefined
          ? opt.label
          : `${opt.label} (${opt.count.toLocaleString()})`
      if (opt.id === selected) {
        el.selected = true
        matched = true
      }
      this.select.appendChild(el)
    }
    // A <select size> greater than 1 does not auto-select an option the way
    // a plain dropdown (size 1) does natively. Mirror that native default
    // explicitly so a facet with no prior/matching selection still starts on
    // its first row instead of sitting fully unselected — this is what lets
    // a cascading facet (e.g. FacetFilter) seed its dependents on first load.
    if (!matched && this.select.options.length > 0) {
      this.select.options[0].selected = true
    }
  }

  get value(): string | null {
    return this.select.value || null
  }

  set value(id: string | null) {
    this.select.value = id ?? ''
  }
}
