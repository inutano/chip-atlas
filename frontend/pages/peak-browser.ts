// frontend/pages/peak-browser.ts
// Genome tabs + FacetFilter (list-box mode, five panels) + IGV/Download actions.
//
// The "Track type (optional)" and "Cell type (optional)" panels pair a
// "type to search" input with the track_subclass / cell_type_subclass list
// boxes that FacetFilter itself renders (production's old Flexselect
// affordance). Autocomplete's own `pairedList` option is not used here: it
// builds a *second*, independent ListBox inside the same container, which
// would fight FacetFilter for ownership of that DOM node (last one to render
// wins) and silently detach FacetFilter's own control — breaking both the
// bidirectional cascade and the value FacetFilter.getCondition() reports for
// that facet. Instead, the input drives the *same* <select> FacetFilter
// already owns: Autocomplete supplies the "type to search" suggestion
// dropdown (built from that select's current options) and, on selection,
// sets the select's value and dispatches a native `change` event — the exact
// event FacetFilter's ListBox control already listens for — so the cascade,
// counts and getCondition() all stay correct. A plain substring filter also
// hides/shows the underlying <option>s as you type, so the list box below
// narrows live, matching the paired-list-box affordance visually.

import { GenomeTabs } from '../components/genome-tabs'
import { FacetFilter, type FacetFilterOptions } from '../components/facet-filter'
import { Autocomplete } from '../components/autocomplete'
import { initInfoPopovers } from '../components/info-popover'
import { getIgvUrl, getDownloadUrl, type UrlCondition } from '../api/client'
import { igvReachable, igvOriginOf, IGV_UNREACHABLE_MESSAGE } from '../components/igv'

interface PageData {
  genomes: Record<string, string>
}

// Copy lifted verbatim from production's js/pj/peak_browser.js helpText object.
const HELP_TEXT: Record<string, string> = {
  threshold:
    'Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV. Colors shown in IGV indicate the statistical significance values as follows: blue (50), cyan (250), green (500), yellow (750), and red (> 1,000).',
}

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

function buildCondition(facet: HTMLElement): UrlCondition | null {
  const c = FacetFilter.getCondition(facet)
  if (!c) return null
  return {
    genome: c.genome,
    track_class: c.track_class,
    track_subclass: c.track_subclass || undefined,
    cell_type_class: c.cell_type_class || undefined,
    cell_type_subclass: c.cell_type_subclass || undefined,
    qval: c.qval || undefined,
  }
}

// ===== "type to search" wiring for the two optional subclass list boxes =====

interface SubclassSearch {
  input: HTMLInputElement
  mount: HTMLElement
  idByLabel: Map<string, string>
}

function subclassSelect(mount: HTMLElement): HTMLSelectElement | null {
  return mount.querySelector('select')
}

function refreshSubclassSearch(s: SubclassSearch): void {
  const select = subclassSelect(s.mount)
  if (!select) return
  const items: string[] = []
  s.idByLabel.clear()
  for (const opt of Array.from(select.options)) {
    const text = opt.textContent ?? opt.value
    items.push(text)
    s.idByLabel.set(text, opt.value)
  }
  Autocomplete.setItems(s.input, items)
}

function wireSubclassSearch(input: HTMLInputElement, mount: HTMLElement): SubclassSearch {
  const s: SubclassSearch = { input, mount, idByLabel: new Map() }

  Autocomplete.init(input, [], (label) => {
    const select = subclassSelect(mount)
    const id = s.idByLabel.get(label)
    if (!select || id === undefined) return
    select.value = id
    select.dispatchEvent(new Event('change', { bubbles: true }))
  })

  // Live-narrow the visible list box as the user types, mirroring the old
  // Flexselect "type to search" behaviour.
  input.addEventListener('input', () => {
    const select = subclassSelect(mount)
    if (!select) return
    const q = input.value.trim().toLowerCase()
    for (const opt of Array.from(select.options)) {
      opt.hidden = q !== '' && !(opt.textContent ?? '').toLowerCase().includes(q)
    }
  })

  return s
}

// Task D2: the FacetFilterOptions this page's genome-change handler passes
// to FacetFilter.init, pulled out into its own exported function (mirroring
// enrichmentFacetFilterOptions in enrichment-analysis.ts) so it can be
// asserted directly — see peak-browser.test.ts. Deliberately passes no
// `excludeTrackClassIds`: unlike Enrichment Analysis, Peak Browser must keep
// every track class FacetFilter is handed, Annotation tracks included.
export function peakBrowserFacetFilterOptions(
  mount: Record<'track_class' | 'track_subclass' | 'cell_type_class' | 'cell_type_subclass' | 'qval', HTMLElement>,
): FacetFilterOptions {
  return { render: 'listbox', mount }
}

async function init(): Promise<void> {
  const data = readPageData()
  const tabs = $('genome-tabs')
  const status = $('action-status')

  // Anchor element for FacetFilter's internal registry / facet-change event.
  // In list-box mode the five facets render into their own mount points
  // (below), so this container never enters the document.
  const facet = document.createElement('div')

  const mount: Record<'track_class' | 'track_subclass' | 'cell_type_class' | 'cell_type_subclass' | 'qval', HTMLElement> = {
    track_class:        $('facet-track-class'),
    track_subclass:     $('facet-track-subclass'),
    cell_type_class:    $('facet-cell-type-class'),
    cell_type_subclass: $('facet-cell-type-subclass'),
    qval:               $('facet-qval'),
  }

  const trackSearch = wireSubclassSearch($('track-subclass-input') as HTMLInputElement, mount.track_subclass)
  const cellSearch = wireSubclassSearch($('cell-type-subclass-input') as HTMLInputElement, mount.cell_type_subclass)

  facet.addEventListener('facet-change', () => {
    refreshSubclassSearch(trackSearch)
    refreshSubclassSearch(cellSearch)
    // Production shows five rows for the significance threshold, not eight.
    const qvalSelect = subclassSelect(mount.qval)
    if (qvalSelect) qvalSelect.size = 5
  })

  tabs.addEventListener('genome-change', async (e: Event) => {
    const detail = (e as CustomEvent<{ genome: string }>).detail
    if (FacetFilter.getCondition(facet)) {
      await FacetFilter.setGenome(facet, detail.genome)
    } else {
      await FacetFilter.init(facet, detail.genome, peakBrowserFacetFilterOptions(mount))
    }
  })

  GenomeTabs.init(tabs, data.genomes)
  initInfoPopovers(document, HELP_TEXT)

  $('view-igv').addEventListener('click', async () => {
    const condition = buildCondition(facet)
    if (!condition) { status.textContent = 'Select a track type first.'; return }
    status.textContent = 'Building IGV link…'
    try {
      const res = await getIgvUrl(condition)
      // Check IGV is actually listening first. Navigating blind lands the user
      // on the browser's connection-error page, which explains nothing.
      status.textContent = 'Contacting IGV\u2026'
      if (!(await igvReachable(igvOriginOf(res.url)))) {
        status.textContent = IGV_UNREACHABLE_MESSAGE
        return
      }
      status.textContent = ''
      window.location.href = res.url
    } catch (err) {
      console.error(err)
      status.textContent = 'Failed to build IGV link.'
    }
  })

  $('download-bed').addEventListener('click', async () => {
    const condition = buildCondition(facet)
    if (!condition) { status.textContent = 'Select a track type first.'; return }
    status.textContent = 'Building download link…'
    try {
      const res = await getDownloadUrl(condition)
      status.textContent = ''
      window.location.href = res.url
    } catch (err) {
      console.error(err)
      status.textContent = 'Failed to build download link.'
    }
  })
}

// Guarded (rather than a bare top-level call) so peakBrowserFacetFilterOptions
// can be imported and unit-tested under plain Node, which has no `document`
// — see peak-browser.test.ts, and enrichment-analysis.ts / colo-result.ts /
// target-genes-result.ts for the same pattern.
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init)
}
