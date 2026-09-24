// frontend/components/info-popover.test.ts
// Unit tests for isOutsideClick, the pure predicate behind R6 (owner
// feedback round 2): info popovers must close on a click anywhere outside
// the trigger and its currently-open popover tip. See info-popover.ts for
// the isOutsideClick export and the shown.bs.popover/hidden.bs.popover
// wiring that calls it at event time (re-resolving the tip via the
// trigger's aria-describedby, since Bootstrap rebuilds the tip element on
// every show). That wiring is DOM/Bootstrap-runtime behavior with no jsdom
// dependency in this repo (script/dev/test-frontend.sh runs pure-logic
// tests only), so it is covered by a headless-browser live check documented
// in the task report instead of here.
//
// isOutsideClick only ever calls Node.contains, so every case below passes
// small duck-typed stand-ins rather than real DOM nodes.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { isOutsideClick } from './info-popover'

const child = { id: 'child' }
const outside = { id: 'outside' }

// A "trigger"/"tip" stand-in that contains exactly `child` and nothing else.
const containsChild = { contains: (n: unknown) => n === child }
// A "trigger"/"tip" stand-in that contains nothing at all.
const containsNothing = { contains: () => false }

test('isOutsideClick: target is null -> false', () => {
  assert.equal(
    isOutsideClick(null, containsChild as unknown as Node, containsNothing as unknown as Node),
    false,
  )
})

test('isOutsideClick: target inside trigger -> false', () => {
  assert.equal(
    isOutsideClick(child as unknown as Node, containsChild as unknown as Node, containsNothing as unknown as Node),
    false,
  )
})

test('isOutsideClick: target inside tip -> false', () => {
  assert.equal(
    isOutsideClick(child as unknown as Node, containsNothing as unknown as Node, containsChild as unknown as Node),
    false,
  )
})

test('isOutsideClick: target elsewhere (in neither trigger nor tip) -> true', () => {
  assert.equal(
    isOutsideClick(outside as unknown as Node, containsChild as unknown as Node, containsChild as unknown as Node),
    true,
  )
})

test('isOutsideClick: tip is null and target elsewhere -> true', () => {
  assert.equal(isOutsideClick(outside as unknown as Node, containsChild as unknown as Node, null), true)
})
