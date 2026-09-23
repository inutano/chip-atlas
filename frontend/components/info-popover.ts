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

// PB-21: production's "Error connecting to IGV?" help (viewOnIGV's
// confirm()) ends with a real link to the IGV download page, which a plain
// help string can't carry. A topic can be either: a plain string (every
// existing topic, rendered as text — `html: false`), or `{ text, link }`,
// rendered as one DocumentFragment (a text node plus a real `<a>`) with
// `html: false` left off for that popover alone. The content is still never
// built from an HTML *string* — see buildLinkedContent — so this does not
// reopen the door to rendering untrusted data as markup.
export interface HelpLink {
  href: string
  label: string
}

export type HelpTopic = string | { text: string; link: HelpLink }

function buildLinkedContent(topic: { text: string; link: HelpLink }): DocumentFragment {
  const fragment = document.createDocumentFragment()
  fragment.appendChild(document.createTextNode(topic.text))
  // Without a separator the text and link butt straight up against each
  // other ("...browse the data.IGV download page"). A blank-line text node
  // renders as a single collapsed space today and, once a future task adds
  // `white-space: pre-line` to .popover-body, as a real paragraph break —
  // either way it separates every current and future linked topic, so it
  // belongs here rather than duplicated into each topic's own `text`.
  fragment.appendChild(document.createTextNode('\n\n'))
  const a = document.createElement('a')
  a.href = topic.link.href
  a.target = '_blank'
  a.rel = 'noopener noreferrer'
  a.textContent = topic.link.label
  fragment.appendChild(a)
  return fragment
}

// Bootstrap 5's Popover constructor, resolved lazily so pages that never
// call initInfoPopovers() don't need window.bootstrap to exist at all.
export function initInfoPopovers(root: ParentNode, helpText: Record<string, HelpTopic>): void {
  const Popover = window.bootstrap?.Popover
  if (!Popover) return

  root.querySelectorAll<HTMLAnchorElement>('.info-btn[data-info]').forEach((btn) => {
    const key = btn.dataset.info
    const topic = key ? helpText[key] : undefined
    if (!topic) return

    new Popover(btn, {
      // A function, not the built fragment itself (2026-09-24 review): a
      // Bootstrap popover disposes its tip on every hide and rebuilds it on
      // the next show by re-resolving this same `content` value
      // (TemplateFactory#_resolvePossibleFunction calls a function value
      // fresh each time, but returns anything else, including a
      // DocumentFragment, unchanged). A DocumentFragment's children move out
      // of it the moment it is first appended into the DOM
      // (TemplateFactory#_putElementInTemplate's `html` branch does
      // `element.append(fragment)`), so handing over one already-built
      // fragment left it empty for every show after the first — verified
      // headless: `.popover-body` was `""` on re-open. A function gets each
      // show its own fragment.
      content: typeof topic === 'string' ? topic : () => buildLinkedContent(topic),
      trigger: 'focus click',
      placement: 'top',
      // `html` does govern element/fragment content, not only markup
      // strings, contrary to what this comment used to claim:
      // TemplateFactory#_putElementInTemplate's non-html branch does
      // `templateElement.textContent = element.textContent`, which reads the
      // fragment's flattened text and drops the real `<a>` element entirely.
      // A linked topic needs `html: true` to keep that link instead of just
      // its text; a raw HTML *string* built from data is still never passed
      // here for either topic shape.
      html: typeof topic !== 'string',
    })

    // The anchors have no real href target; keep them keyboard-focusable
    // (for the "focus" trigger above) without navigating or reloading.
    btn.addEventListener('click', (e) => e.preventDefault())
  })
}
