// frontend/pages/target-genes-result.test.ts
// Unit tests for the pure sort-state logic behind the Target Genes result
// page's column headers and its distance-switch sort fallback.
//
// Run with: bash script/dev/test-frontend.sh
// (esbuild-bundled, then executed with Node's built-in test runner — see
// that script for why: this module transitively imports ApiError from
// ../api/client, which uses a TS parameter-property constructor that
// Node's own --experimental-strip-types cannot handle unassisted, so a
// plain `node --test` on the raw .ts files doesn't work in this repo.)
//
// esbuild.config.mjs already excludes any *.test.ts / *.spec.ts from the
// production page bundle, so this file ships nowhere.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ApiError } from '../api/client'
import { computeAriaSort, computeNextSort, emptyStateMessage, isUnknownSortColumnError } from './target-genes-result'

// ===== computeNextSort — what a header's click handler runs on activation =====
//
// A real <button> fires the identical "click" event whether it was
// activated by a mouse click or by pressing Enter/Space while focused
// (guaranteed native <button> behavior — see makeSortableHeader's comment
// in target-genes-result.ts for why that, not a custom keydown handler, is
// what makes the header keyboard-operable). These tests cover the shared
// state transition that activation runs, by mouse or by keyboard alike;
// see the fix report for why simulating an actual KeyboardEvent isn't also
// exercised here (there's no browser/DOM available in this environment).

test('computeNextSort: a fresh column sorts descending first, matching the server default', () => {
  const next = computeNextSort({ sort: null, order: 'desc' }, 'Stat3|Average')
  assert.deepEqual(next, { sort: 'Stat3|Average', order: 'desc' })
})

test('computeNextSort: activating the already-sorted column flips desc -> asc', () => {
  const next = computeNextSort({ sort: 'STRING', order: 'desc' }, 'STRING')
  assert.deepEqual(next, { sort: 'STRING', order: 'asc' })
})

test('computeNextSort: activating the already-sorted column flips asc -> desc', () => {
  const next = computeNextSort({ sort: 'STRING', order: 'asc' }, 'STRING')
  assert.deepEqual(next, { sort: 'STRING', order: 'desc' })
})

test('computeNextSort: activating a different column switches to it, descending', () => {
  const next = computeNextSort({ sort: 'STRING', order: 'asc' }, 'SRX361677|Astrocytes')
  assert.deepEqual(next, { sort: 'SRX361677|Astrocytes', order: 'desc' })
})

test('computeNextSort: repeated activation (mouse clicks or Enter/Space presses alike) toggles back and forth', () => {
  let s: { sort: string | null; order: 'asc' | 'desc' } = { sort: null, order: 'desc' }
  s = computeNextSort(s, 'Stat3|Average')
  assert.deepEqual(s, { sort: 'Stat3|Average', order: 'desc' })
  s = computeNextSort(s, 'Stat3|Average')
  assert.deepEqual(s, { sort: 'Stat3|Average', order: 'asc' })
  s = computeNextSort(s, 'Stat3|Average')
  assert.deepEqual(s, { sort: 'Stat3|Average', order: 'desc' })
})

// ===== computeAriaSort — the accessible sort-state indication =====

test('computeAriaSort: the active column reports its current direction', () => {
  assert.equal(computeAriaSort({ sort: 'STRING', order: 'desc' }, 'STRING'), 'descending')
  assert.equal(computeAriaSort({ sort: 'STRING', order: 'asc' }, 'STRING'), 'ascending')
})

test('computeAriaSort: every other column reports none', () => {
  assert.equal(computeAriaSort({ sort: 'STRING', order: 'desc' }, 'Stat3|Average'), 'none')
  assert.equal(computeAriaSort({ sort: null, order: 'desc' }, 'STRING'), 'none')
})

// ===== isUnknownSortColumnError — the distance-switch sort fallback trigger =====
//
// routes/api.rb halts 400 for TargetGenesTsv::UnknownSortColumn (a sort
// column that doesn't exist in the fetched TSV's header row — reachable
// when a sort persists across a distance switch to a file with a
// different column set) and 404 for a genuinely missing combination.
// load() in target-genes-result.ts must tell these apart: the first
// should fall back to the default sort and retry, the second should show
// the "no precomputed data" message. Both halts are JSON, so ApiError is
// the only signal available client-side — this is deliberately a status
// check, not a body/message check, matching what the client can actually
// see.

test('isUnknownSortColumnError: true for a 400 (TargetGenesTsv::UnknownSortColumn)', () => {
  const err = new ApiError(400, 'Bad Request', '{"error":"Unknown sort column: \\"SRX999|Foo\\""}')
  assert.equal(isUnknownSortColumnError(err), true)
})

test('isUnknownSortColumnError: false for a 404 (genuinely missing combination)', () => {
  const err = new ApiError(404, 'Not Found', '{"error":"Target genes data not found"}')
  assert.equal(isUnknownSortColumnError(err), false)
})

test('isUnknownSortColumnError: false for a 502 (upstream parse error)', () => {
  const err = new ApiError(502, 'Bad Gateway', '{"error":"Target genes data could not be parsed"}')
  assert.equal(isUnknownSortColumnError(err), false)
})

test('isUnknownSortColumnError: false for a non-ApiError (e.g. a network failure)', () => {
  assert.equal(isUnknownSortColumnError(new TypeError('Failed to fetch')), false)
})

// ===== emptyStateMessage — the F2 fix: two different empty facts must read
// differently, or a gene search that matches nothing looks identical to
// "this antigen/distance has no precomputed data at all" (the bug that got
// the previous client-side filter removed - see task-F2-brief.md). =====

test('emptyStateMessage: no active gene filter reads as "no target genes found"', () => {
  assert.equal(emptyStateMessage(''), 'No target genes found')
})

test('emptyStateMessage: an active gene filter with zero matches names the query, distinctly from the no-filter case', () => {
  const withQuery = emptyStateMessage('Zzznosuchgene')
  assert.equal(withQuery, 'No genes match "Zzznosuchgene".')
  assert.notEqual(withQuery, emptyStateMessage(''))
})

test('emptyStateMessage: the query text is interpolated as plain text, not treated as markup', () => {
  // This only proves the *string* has no markup baked in; the actual DOM
  // safety guarantee is that renderPagination() assigns this via
  // .textContent (never .innerHTML) - see target-genes-result.ts.
  const message = emptyStateMessage('<img src=x>')
  assert.equal(message, 'No genes match "<img src=x>".')
})
