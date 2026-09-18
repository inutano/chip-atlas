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
