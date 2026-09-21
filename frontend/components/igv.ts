// Reachability check for IGV's command port.
//
// IGV desktop listens on http://localhost:60151 and takes commands as plain
// GETs (`/load?file=…`). Both the Peak Browser's "View on IGV" button and the
// experiment page's Visualize menu used to hand that URL straight to the
// browser, so with IGV not running the user was navigated off ChIP-Atlas onto
// the browser's own connection-error page - which names neither IGV nor the
// port, and loses whatever they had selected.
//
// The port speaks no CORS, so a cross-origin response can never be read. That
// does not matter here: `mode: 'no-cors'` still distinguishes the two cases we
// care about. A refused connection REJECTS the fetch; a connection that is
// accepted RESOLVES, opaque body and all. Any reply counts as reachable, so
// the probe does not depend on IGV supporting a particular command.
//
// Note browsers treat http://localhost as a potentially-trustworthy origin,
// so this is not blocked as mixed content when ChIP-Atlas itself is served
// over https.

export const IGV_ORIGIN = 'http://localhost:60151'

export const IGV_UNREACHABLE_MESSAGE =
  'Could not reach IGV on localhost:60151. Start IGV on this machine and make ' +
  'sure "Enable port" is on under View › Preferences › Advanced, then try again.'

/** Resolves true when something accepts a connection on IGV's port. */
export async function igvReachable(origin: string = IGV_ORIGIN, timeoutMs = 2000): Promise<boolean> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    await fetch(`${origin}/echo`, {
      mode: 'no-cors',
      cache: 'no-store',
      signal: controller.signal,
    })
    return true
  } catch {
    return false
  } finally {
    clearTimeout(timer)
  }
}

/** The origin of an IGV command URL, for probing before navigating to it. */
export function igvOriginOf(url: string): string {
  try {
    return new URL(url).origin
  } catch {
    return IGV_ORIGIN
  }
}
