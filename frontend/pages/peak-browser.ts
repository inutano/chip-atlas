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
import { FacetFilter, type FacetFilterOptions, type FacetKey } from '../components/facet-filter'
import { Autocomplete } from '../components/autocomplete'
import { initInfoPopovers, type HelpTopic } from '../components/info-popover'
import { getIgvUrl, getDownloadUrl, type UrlCondition } from '../api/client'
import { igvReachable, igvOriginOf, IGV_UNREACHABLE_MESSAGE } from '../components/igv'

interface PageData {
  genomes: Record<string, string>
}

// Copy lifted verbatim from production's js/pj/peak_browser.js helpText object
// (viewOnIGV's text drops its last sentence — "Click OK to go to the IGV
// website, or cancel to back to ChIP-Atlas." — which described a confirm()
// dialog's OK/cancel buttons that the popover form of this help has no
// equivalent of; the real link below replaces what that OK button did).
const HELP_TEXT: Record<string, HelpTopic> = {
  threshold:
    'Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV. Colors shown in IGV indicate the statistical significance values as follows: blue (50), cyan (250), green (500), yellow (750), and red (> 1,000).',
  igv: {
    text:
      'IGV must be running on your computer before clicking the button.\n\n' +
      'If your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 ' +
      '(from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) ' +
      'to browse the data.',
    link: { href: 'https://igv.org/doc/desktop/#DownloadPage/', label: 'IGV download page' },
  },
}

// No precomputed bedfile exists for the selected combination (PB-23) — the
// server can only report {"url": null}, it has no other combination to
// suggest, so this names the fix in the user's own terms rather than a raw
// null. Shown in #action-status instead of navigating to it (production and
// this app's own pre-fix behaviour both land on window.location.href = null,
// i.e. a same-origin "/null" 404 page).
const NO_PRECOMPUTED_FILE_MESSAGE =
  'No precomputed file exists for this combination. Try a different track type, cell type or threshold.'

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

// ===== PB-16: antigen ⇄ cell-type mutual exclusion =====
// Production (peak_browser.js:318-360) never lets both optional panels hold
// a real ("-"-is-"All") selection at once: whichever one the user did NOT
// just change gets reset back to "-", and a warning explains why. bedfiles
// has no rows where both track_subclass and cell_type_subclass are set
// (confirmed locally — see docs/review-2026-09-23/findings/ui-peak-browser.md
// PB-16), so without this a combination that looks selectable resolves to a
// null URL (PB-23) instead.

// Pure decision step, kept separate from the DOM reads/writes below so it can
// be unit-tested without a DOM — see peak-browser.test.ts.
export function resolveSubclassExclusion(
  changed: 'track_subclass' | 'cell_type_subclass',
  track: string,
  cell: string,
): { resetFacet: 'track_subclass' | 'cell_type_subclass' | null } {
  if (track === '-' || cell === '-') return { resetFacet: null }
  return { resetFacet: changed === 'track_subclass' ? 'cell_type_subclass' : 'track_subclass' }
}

const SUBCLASS_WARNING_TEXT = 'Either an "Antigen" or a "Cell type" is selectable.'

function buildSubclassWarning(): HTMLDivElement {
  const div = document.createElement('div')
  div.className = 'alert alert-warning alert-dismissible fade show'
  div.setAttribute('role', 'alert')
  div.textContent = SUBCLASS_WARNING_TEXT
  const closeButton = document.createElement('button')
  closeButton.type = 'button'
  closeButton.className = 'btn-close'
  closeButton.dataset.bsDismiss = 'alert'
  closeButton.setAttribute('aria-label', 'Close')
  div.appendChild(closeButton)
  return div
}

// Applies the exclusion for one facet-change event. No-op unless the facet
// that just changed is one of the two optional subclass facets themselves —
// every other facet-change (track_class, cell_type_class, qval, init) leaves
// both alone. The reset goes through the facet's own <select> (native
// `change`, not FacetFilter's internal state directly) so FacetFilter's own
// cascade and counts stay consistent; the resulting second facet-change sees
// one side as "-" and does nothing (resolveSubclassExclusion returns null).
function applySubclassExclusion(
  changedFacet: FacetKey | 'init',
  trackSelect: HTMLSelectElement,
  cellSelect: HTMLSelectElement,
  warningContainer: HTMLElement,
): void {
  if (changedFacet !== 'track_subclass' && changedFacet !== 'cell_type_subclass') return

  const { resetFacet } = resolveSubclassExclusion(changedFacet, trackSelect.value, cellSelect.value)
  if (!resetFacet) return

  const select = resetFacet === 'track_subclass' ? trackSelect : cellSelect
  select.value = '-'
  select.dispatchEvent(new Event('change', { bubbles: true }))

  // Only one warning at a time: replace rather than append.
  warningContainer.replaceChildren(buildSubclassWarning())
}

// Production hardcodes the significance-threshold list box to size=5
// regardless of how many real options it holds (confirmed against production
// for the normal four-option case — see ui-peak-browser.md's "差分なしを確認
// した事項" — so the ordinary Histone/RNA polymerase/TFs and others case must
// keep production's five rows, blank trailing row and all). The one
// exception is Bisulfite-Seq/Annotation tracks' single fixed "NA" option
// (Task 2's qvalOptionsFor): four blank rows under one real row reads as
// broken, not as parity, so that degenerate case alone shrinks to 2. Pure
// and exported so the size math has its own coverage, separate from the DOM
// wiring in the facet-change listener — see peak-browser.test.ts.
export function qvalListBoxSize(optionCount: number): number {
  return optionCount <= 1 ? 2 : 5
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
  const subclassWarning = $('subclass-warning')

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

  facet.addEventListener('facet-change', (e: Event) => {
    refreshSubclassSearch(trackSearch)
    refreshSubclassSearch(cellSearch)
    const qvalSelect = subclassSelect(mount.qval)
    if (qvalSelect) qvalSelect.size = qvalListBoxSize(qvalSelect.options.length)

    const trackSubclassSelect = subclassSelect(mount.track_subclass)
    const cellTypeSubclassSelect = subclassSelect(mount.cell_type_subclass)
    if (trackSubclassSelect && cellTypeSubclassSelect) {
      const changedFacet = (e as CustomEvent<{ facet: FacetKey | 'init' }>).detail.facet
      applySubclassExclusion(changedFacet, trackSubclassSelect, cellTypeSubclassSelect, subclassWarning)
    }
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
      // PB-23: no precomputed bedfile for this combination, so stay on the
      // page rather than navigate to `window.location.href = null` (a
      // same-origin "/null" 404), and skip the reachability probe below:
      // there is no URL for it to check.
      if (!res.url) {
        status.textContent = NO_PRECOMPUTED_FILE_MESSAGE
        return
      }
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
      // PB-23: see the matching check in the View on IGV handler above.
      if (!res.url) {
        status.textContent = NO_PRECOMPUTED_FILE_MESSAGE
        return
      }
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
