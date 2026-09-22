// frontend/components/job-tracker.test.ts
// Unit tests for the pure logic behind the job-info table on the two analysis
// result pages (views/{enrichment,diff}_analysis_result.erb).
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  estimatedFinish,
  formatStamp,
  parseEstimateMinutes,
  parseWabiSubmitTime,
} from './job-tracker'
import { readResultPageParams } from './result-page-params'

// ===== parseWabiSubmitTime =====
//
// WABI stamps its request IDs in DDBJ's own timezone. The two cases below are
// real finished jobs, checked against the `Start:` line in each one's own
// execution log — which WABI writes with an explicit offset, so the reading is
// not an inference:
//
//   wabi_chipatlas_2026-0922-1049-51-290-755138
//     -> Start: 2026-09-22T10:50:21+09:00  (30s after the stamp)
//   wabi_chipatlas_2026-0922-0427-11-615-719546
//     -> Start: 2026-09-22T04:27:37+09:00  (26s after the stamp)
//
// Reading the stamp as UTC instead would put both submissions nine hours
// before their own jobs started, so these assert the absolute instant rather
// than any rendered string — a test written in local time would pass on a
// JST machine no matter which way round it was.

test('parseWabiSubmitTime: reads the stamp as JST, the timezone WABI writes it in', () => {
  const t = parseWabiSubmitTime('wabi_chipatlas_2026-0922-1049-51-290-755138')
  assert.ok(t)
  assert.equal(t.toISOString(), '2026-09-22T01:49:51.000Z')
})

test('parseWabiSubmitTime: a second real job, across a different hour', () => {
  const t = parseWabiSubmitTime('wabi_chipatlas_2026-0922-0427-11-615-719546')
  assert.ok(t)
  // 04:27:11 JST is the previous day in UTC — the case that would go
  // unnoticed if the stamp were read as UTC and only same-day IDs tested.
  assert.equal(t.toISOString(), '2026-09-21T19:27:11.000Z')
})

test('parseWabiSubmitTime: the submission always precedes the job start in its own log', () => {
  const submitted = parseWabiSubmitTime('wabi_chipatlas_2026-0922-1049-51-290-755138')
  assert.ok(submitted)
  const loggedStart = new Date('2026-09-22T10:50:21+09:00')
  const gapSeconds = (loggedStart.getTime() - submitted.getTime()) / 1000
  assert.ok(gapSeconds > 0 && gapSeconds < 300, `queue hand-off gap was ${gapSeconds}s`)
})

test('parseWabiSubmitTime: null for an ID that is not WABI\'s shape', () => {
  // The caller falls back to page-load time, which is what production always
  // does. A WES/Sapporo run ID is a UUID, and a hand-typed URL can hold
  // anything at all.
  assert.equal(parseWabiSubmitTime('3fa85f64-5717-4562-b3fc-2c963f66afa6'), null)
  assert.equal(parseWabiSubmitTime(''), null)
  assert.equal(parseWabiSubmitTime('wabi_chipatlas_nonsense'), null)
  // Right prefix, wrong field widths — must not be coerced into a date.
  assert.equal(parseWabiSubmitTime('wabi_chipatlas_2026-922-1049-51-290-755138'), null)
})

test('parseWabiSubmitTime: null for a stamp that names no real instant', () => {
  assert.equal(parseWabiSubmitTime('wabi_chipatlas_2026-1332-1049-51-290-755138'), null)
})

// ===== parseEstimateMinutes =====
//
// The estimate is carried to this page as the literal string the submit
// panel was showing. Production's two formats are "<n> mins" and "<n.n> hr";
// see enrichment-analysis.ts's formatEstimate, which produces them, and
// diff-analysis.ts, which writes "<n> mins" for the server-side estimate.

test('parseEstimateMinutes: minutes', () => {
  assert.equal(parseEstimateMinutes('13 mins'), 13)
  assert.equal(parseEstimateMinutes('0 mins'), 0)
  assert.equal(parseEstimateMinutes('59 mins'), 59)
})

test('parseEstimateMinutes: hours, including the fractional form', () => {
  assert.equal(parseEstimateMinutes('1.0 hr'), 60)
  assert.equal(parseEstimateMinutes('1.6 hr'), 96)
  assert.equal(parseEstimateMinutes('2.3 hr'), 138)
})

test('parseEstimateMinutes: null when there was no estimate to carry', () => {
  // Production renders this case as the string "Invalid Date" in the table:
  // its parser falls through to `undefined`, parseInt makes that NaN, and
  // adding NaN minutes to a Date poisons it. An em dash says the same thing
  // without looking like a crash.
  assert.equal(parseEstimateMinutes(''), null)
  assert.equal(parseEstimateMinutes('—'), null)
  assert.equal(parseEstimateMinutes('-'), null)
  assert.equal(parseEstimateMinutes('(failed)'), null)
})

test('parseEstimateMinutes: null rather than a partial read of an unknown format', () => {
  assert.equal(parseEstimateMinutes('13'), null)
  assert.equal(parseEstimateMinutes('13 seconds'), null)
  assert.equal(parseEstimateMinutes('about 13 mins'), null)
})

// ===== estimatedFinish =====

test('estimatedFinish: adds the estimate to the submission time', () => {
  const submitted = new Date('2026-09-22T10:49:51+09:00')
  assert.equal(
    estimatedFinish(submitted, '13 mins')?.toISOString(),
    '2026-09-22T02:02:51.000Z',
  )
  assert.equal(
    estimatedFinish(submitted, '1.6 hr')?.toISOString(),
    '2026-09-22T03:25:51.000Z',
  )
})

test('estimatedFinish: null when there is no estimate, not the submission time', () => {
  // Returning `submitted` unchanged would claim the job finishes the instant
  // it was queued, which reads as a real answer.
  assert.equal(estimatedFinish(new Date('2026-09-22T10:49:51+09:00'), ''), null)
})

test('estimatedFinish: does not mutate the date it was given', () => {
  // Production's setEstFinish calls now.setMinutes(...) on the same Date it
  // also used for "Submitted at", so computing the finishing time moves the
  // submission time with it.
  const submitted = new Date('2026-09-22T10:49:51+09:00')
  const before = submitted.getTime()
  estimatedFinish(submitted, '13 mins')
  assert.equal(submitted.getTime(), before)
})

// ===== formatStamp =====

test('formatStamp: production\'s "HH:MM:SS (Mon-DD-YYYY)", local then UTC', () => {
  // Asserted through the UTC half, which is the same on every machine. The
  // local half is the same instant rendered in whatever zone the reader is in.
  const stamp = formatStamp(new Date('2026-09-22T01:49:51Z'))
  assert.match(stamp, / \/ UTC: 01:49:51 \(Sep-22-2026\)$/)
  assert.match(stamp, /^\d{2}:\d{2}:\d{2} \([A-Z][a-z]{2}-\d{2}-\d{4}\)/)
})

test('formatStamp: pads single digits in both halves', () => {
  const stamp = formatStamp(new Date('2026-01-05T03:04:05Z'))
  assert.match(stamp, /UTC: 03:04:05 \(Jan-05-2026\)$/)
})

test('formatStamp: an em dash for a date that names no instant', () => {
  assert.equal(formatStamp(new Date('nope')), '—')
})

// ===== readResultPageParams =====

test('readResultPageParams: reads the four values the submit pages send', () => {
  assert.deepEqual(
    readResultPageParams('?id=wabi_chipatlas_ID&backend=wabi&title=My%20project&calcm=13%20mins'),
    { jobId: 'wabi_chipatlas_ID', backend: 'wabi', title: 'My project', calcm: '13 mins' },
  )
})

test('readResultPageParams: title and calcm are optional, id and backend are not', () => {
  // A URL bookmarked before those were carried — or typed by hand — still
  // tracks the job; the two cells just show an em dash.
  assert.deepEqual(readResultPageParams('?id=X&backend=wabi'), {
    jobId: 'X', backend: 'wabi', title: '', calcm: '',
  })
  assert.equal(readResultPageParams('?backend=wabi'), null)
  assert.equal(readResultPageParams('?id=X'), null)
  assert.equal(readResultPageParams(''), null)
})

test('readResultPageParams: a title with & or = in it survives the round trip', () => {
  const title = 'A&B = my "project"'
  const search = `?id=X&backend=wabi&title=${encodeURIComponent(title)}&calcm=13%20mins`
  assert.equal(readResultPageParams(search)?.title, title)
})
