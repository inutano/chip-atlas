#!/usr/bin/env node
// Regression check for the Target Genes result page's "expanded experiment
// columns must not scroll the document horizontally" constraint.
//
// #result-table-wrap has overflow-x:auto and does correctly contain/scroll
// its own content — but that alone wasn't enough: with 130+ columns of
// unbreakable header text, the wrapper's intrinsic content width (tens of
// thousands of pixels) still reached document.documentElement's own
// reported scrollWidth (a real, root-element-specific quirk — see
// public/css/style.css's #result-table-wrap comment), and in a mobile
// viewport that visibly widened the whole layout viewport and dragged the
// 100%-wide fixed navbar out past the screen edge with it. The fix is
// `contain: layout paint` on #result-table-wrap. This script measures
// document.documentElement.scrollWidth vs clientWidth the same way that
// regression was originally found and fixed, so it can be re-run whenever
// this page changes.
//
// Drives a real headless Chromium directly over the DevTools Protocol
// (no puppeteer/playwright dependency — Node's built-in fetch + WebSocket
// are enough). A resized *window* doesn't reproduce this: Chromium clamps
// windows to a ~500px floor, so a true mobile check needs
// Emulation.setDeviceMetricsOverride, not a small browser window.
//
// Usage:
//   1. Start Chromium headless with a debugging port:
//        chromium --headless=new --disable-gpu --no-sandbox \
//          --remote-debugging-port=9333 --user-data-dir=/tmp/cdp-profile about:blank &
//   2. Start the app (e.g. bash ~/run/chip-atlas-local.sh) so BASE_URL below answers.
//   3. node script/dev/measure-target-genes-overflow.mjs [BASE_URL] [CDP_PORT]
//
// Exits non-zero (and prints which state failed) if any measured state has
// document.documentElement.scrollWidth > clientWidth.

const BASE_URL = process.argv[2] || 'http://localhost:9292'
const CDP_PORT = process.argv[3] || '9333'
const CDP_HOST = `http://localhost:${CDP_PORT}`
const TARGET_URL = `${BASE_URL}/target_genes_result?genome=mm10&track=Stat3&distance=1`

// Minimum px by which the expanded #result-table-wrap's own scrollWidth
// must exceed the viewport for an "expanded" case to be trusted at all -
// see the precondition check in main() below. The real mm10/Stat3.1
// fixture measures 13,000-24,000px of overflow at a 390px viewport, so
// 2,000px leaves ample margin for legitimate data drift while still
// catching the fixture becoming too narrow to mean anything.
const MIN_EXPANDED_OVERFLOW_PX = 2000

async function newTab() {
  const res = await fetch(`${CDP_HOST}/json/new?about:blank`, { method: 'PUT' })
  if (!res.ok) {
    throw new Error(`Could not reach headless Chromium's DevTools endpoint at ${CDP_HOST} (${res.status}). ` +
      'Start it first — see this script\'s header comment for the command.')
  }
  return res.json()
}

function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl)
    ws.addEventListener('open', () => resolve(ws))
    ws.addEventListener('error', reject)
  })
}

function cdp(ws, method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = Math.floor(Math.random() * 1e9)
    const handler = (ev) => {
      const msg = JSON.parse(ev.data)
      if (msg.id === id) {
        ws.removeEventListener('message', handler)
        if (msg.error) reject(new Error(JSON.stringify(msg.error)))
        else resolve(msg.result)
      }
    }
    ws.addEventListener('message', handler)
    ws.send(JSON.stringify({ id, method, params }))
  })
}

function waitForEvent(ws, method, timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      ws.removeEventListener('message', handler)
      reject(new Error(`Timed out waiting for ${method}`))
    }, timeoutMs)
    const handler = (ev) => {
      const msg = JSON.parse(ev.data)
      if (msg.method === method) {
        clearTimeout(timer)
        ws.removeEventListener('message', handler)
        resolve(msg.params)
      }
    }
    ws.addEventListener('message', handler)
  })
}

async function evaluate(ws, expression) {
  const result = await cdp(ws, 'Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails))
  return result.result.value
}

async function measure(ws, width, mobile, expand) {
  await cdp(ws, 'Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile })
  await evaluate(ws, `new Promise(r => setTimeout(r, 150))`) // let the viewport change settle
  // Idempotent either way — this drives one page load through multiple
  // cases in sequence, so each call must land on the requested state
  // regardless of what the previous case left it in.
  await evaluate(ws, `
    (() => {
      const details = document.getElementById('experiments-toggle')
      if (details.open !== ${expand}) document.querySelector('#experiments-toggle summary').click()
    })()
  `)
  await evaluate(ws, `new Promise(r => setTimeout(r, 150))`)

  return evaluate(ws, `
    (() => {
      const de = document.documentElement
      const nav = document.querySelector('nav.navbar')
      const wrap = document.getElementById('result-table-wrap')
      return {
        viewportWidth: window.innerWidth,
        docScrollWidth: de.scrollWidth,
        docClientWidth: de.clientWidth,
        navRight: nav ? nav.getBoundingClientRect().right : null,
        wrapClientWidth: wrap ? wrap.clientWidth : null,
        wrapScrollWidth: wrap ? wrap.scrollWidth : null,
      }
    })()
  `)
}

async function main() {
  const tab = await newTab()
  const ws = await connect(tab.webSocketDebuggerUrl)
  await cdp(ws, 'Page.enable')
  await cdp(ws, 'Runtime.enable')
  await cdp(ws, 'Emulation.setDeviceMetricsOverride', { width: 390, height: 900, deviceScaleFactor: 1, mobile: true })

  const loadPromise = waitForEvent(ws, 'Page.loadEventFired')
  await cdp(ws, 'Page.navigate', { url: TARGET_URL })
  await loadPromise

  await evaluate(ws, `new Promise((resolve, reject) => {
    const deadline = Date.now() + 15000
    const check = () => {
      const wrap = document.getElementById('result-wrap')
      if (wrap && !wrap.hidden) return resolve(true)
      const err = document.getElementById('error-state')
      if (err && !err.hidden) return reject(new Error('error-state shown: ' + err.textContent))
      if (Date.now() > deadline) return reject(new Error('timed out waiting for #result-wrap'))
      setTimeout(check, 100)
    }
    check()
  })`)

  const cases = [
    ['collapsed 390px (mobile)', 390, true, false],
    ['expanded 390px (mobile)', 390, true, true],
    ['expanded 1440px (desktop)', 1440, false, true],
    ['collapsed 1440px (desktop)', 1440, false, false],
  ]

  let allPass = true
  for (const [label, width, mobile, expand] of cases) {
    const m = await measure(ws, width, mobile, expand)

    // Precondition: an "expanded" case only exercises the regression this
    // script exists to catch if the expanded table is actually wide enough
    // to overflow the viewport in the first place. Without this check, a
    // pass condition of docScrollWidth <= docClientWidth is vacuous the
    // moment mm10/Stat3.1's column count (currently 134, ~13,000-24,000px
    // wide at 390px per the comment above) ever shrinks below what it
    // takes to overflow 390px - the script would report PASS while no
    // longer testing anything. MIN_EXPANDED_OVERFLOW_PX is set two orders
    // of magnitude below the actual observed overflow, so real fixture
    // shrinkage that still leaves a meaningful regression test trips this
    // long before it silently goes vacuous.
    if (expand) {
      const overflowPx = m.wrapScrollWidth - m.viewportWidth
      if (overflowPx < MIN_EXPANDED_OVERFLOW_PX) {
        throw new Error(
          `PRECONDITION FAILED for "${label}": the expanded #result-table-wrap is only ` +
          `${overflowPx}px wider than the ${m.viewportWidth}px viewport (wrapScrollWidth=` +
          `${m.wrapScrollWidth}), short of the ${MIN_EXPANDED_OVERFLOW_PX}px this script requires ` +
          'to trust a PASS here. That means the fixture (mm10/Stat3.1, or whichever antigen ' +
          'TARGET_URL now points at) no longer has enough experiment columns to genuinely ' +
          "overflow the viewport when expanded, so a PASS below would not prove the document-" +
          'level overflow-containment fix (contain: layout paint on #result-table-wrap, see ' +
          "public/css/style.css) still works - it would just mean there's nothing to contain. " +
          'Point TARGET_URL at an antigen/genome with more experiment columns, or lower ' +
          'MIN_EXPANDED_OVERFLOW_PX only if you have confirmed by other means that this case ' +
          'still exercises the regression.'
        )
      }
    }

    const pass = m.docScrollWidth <= m.docClientWidth
    allPass = allPass && pass
    console.log(`${pass ? 'PASS' : 'FAIL'}  ${label}`)
    console.log(`      documentElement.scrollWidth=${m.docScrollWidth} clientWidth=${m.docClientWidth}` +
      ` | wrapper scrollWidth=${m.wrapScrollWidth} clientWidth=${m.wrapClientWidth}` +
      ` | navbar right=${m.navRight} viewportWidth=${m.viewportWidth}`)
  }

  await cdp(ws, 'Target.closeTarget', { targetId: tab.id })
  console.log(`\n${allPass ? 'ALL PASS' : 'FAIL'}`)
  process.exit(allPass ? 0 : 1)
}

main().catch((err) => {
  console.error(err.message)
  process.exit(1)
})
