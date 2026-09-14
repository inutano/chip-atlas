// frontend/components/info-popover.ts
//
// Wires Bootstrap 5 popovers onto `.info-btn[data-info="KEY"]` anchors.
//
// Production wires the same ⓘ anchors to blocking `alert(helpText[...])`
// calls (see `js/pj/peak_browser.js` and `js/pj/enrichment_analysis.js`'s
// `$(".infoBtn").click` handlers). We deliberately do not reproduce that
// mechanism here: a blocking `alert()` is poor UX and cannot be exercised by
// headless browser automation. Bootstrap's popover (already vendored via
// /js/bootstrap.bundle.min.js, loaded before any page module — see
// views/layout.erb) gives the same at-a-glance help without blocking the
// page. The copy shown is still lifted verbatim from production's helpText
// objects; only the presentation mechanism changed.

declare global {
  interface Window {
    bootstrap?: {
      Popover: new (
        element: Element,
        options?: Record<string, unknown>,
      ) => { toggle(): void; hide(): void; dispose(): void }
    }
  }
}

// Bootstrap 5's Popover constructor, resolved lazily so pages that never
// call initInfoPopovers() don't need window.bootstrap to exist at all.
export function initInfoPopovers(root: ParentNode, helpText: Record<string, string>): void {
  const Popover = window.bootstrap?.Popover
  if (!Popover) return

  root.querySelectorAll<HTMLAnchorElement>('.info-btn[data-info]').forEach((btn) => {
    const key = btn.dataset.info
    const text = key ? helpText[key] : undefined
    if (!text) return

    new Popover(btn, {
      content: text,
      trigger: 'focus click',
      placement: 'top',
      html: false,
    })

    // The anchors have no real href target; keep them keyboard-focusable
    // (for the "focus" trigger above) without navigating or reloading.
    btn.addEventListener('click', (e) => e.preventDefault())
  })
}
