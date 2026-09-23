// frontend/components/result-page-params.test.ts
// Unit tests for readResultPageParams, the query-string contract for the two
// analysis result pages. See result-page-params.ts's header for why this is
// its own module and its own test file.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readResultPageParams } from './result-page-params'

// ===== backend resolution =====
//
// Production never named a `backend` parameter at all -- it only ever talked
// to WABI. Diff Analysis's redirect carried no backend hint of any kind;
// Enrichment Analysis's carried `api=wabi`. This app routes to WABI or WES,
// so it reads `backend=` first (its own format), falls back to translating
// production's `api=`, and finally defaults to `wabi` for a bare `?id=…`
// (production's diff-analysis shape).

test('readResultPageParams: id alone defaults the backend to wabi (production\'s diff-analysis redirect carried no backend hint at all)', () => {
  assert.deepEqual(readResultPageParams('?id=x'), {
    jobId: 'x', backend: 'wabi', title: '', calcm: '',
  })
})

test('readResultPageParams: api=wabi (production\'s enrichment-analysis redirect) resolves to wabi', () => {
  assert.equal(readResultPageParams('?id=x&api=wabi')?.backend, 'wabi')
})

test('readResultPageParams: any other api= value resolves to wes -- production named a protocol/host, this app names the backend', () => {
  assert.equal(readResultPageParams('?id=x&api=https://ea.chip-atlas.org')?.backend, 'wes')
})

test('readResultPageParams: backend= (this app\'s own format) is read directly and wins over api=', () => {
  assert.equal(readResultPageParams('?id=x&backend=wes')?.backend, 'wes')
  assert.equal(readResultPageParams('?id=x&backend=wes&api=wabi')?.backend, 'wes')
})

test('readResultPageParams: an empty backend= or api= is treated as absent', () => {
  assert.equal(readResultPageParams('?id=x&backend=')?.backend, 'wabi')
  assert.equal(readResultPageParams('?id=x&api=')?.backend, 'wabi')
})

// ===== id is the only required parameter =====

test('readResultPageParams: null when id is missing, even with other parameters present', () => {
  assert.equal(readResultPageParams('?title=x'), null)
  assert.equal(readResultPageParams('?backend=wabi'), null)
  assert.equal(readResultPageParams(''), null)
})

test('readResultPageParams: null when id is present but empty', () => {
  assert.equal(readResultPageParams('?id='), null)
})

// ===== title and calcm remain optional =====

test('readResultPageParams: title and calcm default to empty when absent', () => {
  assert.deepEqual(readResultPageParams('?id=X&backend=wabi'), {
    jobId: 'X', backend: 'wabi', title: '', calcm: '',
  })
})

test('readResultPageParams: reads all four values when present', () => {
  assert.deepEqual(
    readResultPageParams('?id=wabi_chipatlas_ID&backend=wabi&title=My%20project&calcm=13%20mins'),
    { jobId: 'wabi_chipatlas_ID', backend: 'wabi', title: 'My project', calcm: '13 mins' },
  )
})

test('readResultPageParams: a title with & or = in it survives the round trip', () => {
  const title = 'A&B = my "project"'
  const search = `?id=X&backend=wabi&title=${encodeURIComponent(title)}&calcm=13%20mins`
  assert.equal(readResultPageParams(search)?.title, title)
})
