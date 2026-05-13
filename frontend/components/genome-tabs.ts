// frontend/components/genome-tabs.ts
// Bootstrap 5 nav-tabs for genome selection. Persists choice in #genome=<code>.

export interface GenomeChangeDetail {
  genome: string
}

function readGenomeFromHash(): string | null {
  const match = window.location.hash.match(/genome=([\w-]+)/)
  return match ? match[1] : null
}

function writeGenomeToHash(genome: string): void {
  const hash = window.location.hash.replace(/(^#?|&)genome=[\w-]+/, '').replace(/^&/, '')
  const next = hash ? `#${hash}&genome=${genome}` : `#genome=${genome}`
  history.replaceState(null, '', next)
}

function dispatchChange(container: HTMLElement, genome: string): void {
  container.dispatchEvent(new CustomEvent<GenomeChangeDetail>('genome-change', {
    detail: { genome },
    bubbles: false,
  }))
}

function pickInitialGenome(genomes: Record<string, string>): string {
  const fromHash = readGenomeFromHash()
  if (fromHash && fromHash in genomes) return fromHash
  return Object.keys(genomes)[0] || ''
}

export const GenomeTabs = {
  init(container: HTMLElement, genomes: Record<string, string>): void {
    const codes = Object.keys(genomes)
    if (codes.length === 0) {
      container.innerHTML = ''
      return
    }

    const initial = pickInitialGenome(genomes)

    const ul = document.createElement('ul')
    ul.className = 'nav nav-tabs mb-3'
    ul.setAttribute('role', 'tablist')

    for (const code of codes) {
      const li = document.createElement('li')
      li.className = 'nav-item'
      li.setAttribute('role', 'presentation')

      const button = document.createElement('button')
      button.type = 'button'
      button.className = 'nav-link' + (code === initial ? ' active' : '')
      button.setAttribute('role', 'tab')
      button.setAttribute('aria-selected', code === initial ? 'true' : 'false')
      button.dataset.genome = code
      button.textContent = code
      button.title = genomes[code]

      button.addEventListener('click', () => {
        ul.querySelectorAll<HTMLButtonElement>('button.nav-link').forEach((b) => {
          const active = b === button
          b.classList.toggle('active', active)
          b.setAttribute('aria-selected', active ? 'true' : 'false')
        })
        writeGenomeToHash(code)
        dispatchChange(container, code)
      })

      li.appendChild(button)
      ul.appendChild(li)
    }

    container.replaceChildren(ul)

    // Emit an initial event so callers can render the starting state.
    if (initial) {
      writeGenomeToHash(initial)
      dispatchChange(container, initial)
    }
  },

  getSelected(container: HTMLElement): string | null {
    const active = container.querySelector<HTMLButtonElement>('button.nav-link.active')
    return active?.dataset.genome ?? null
  },
}
