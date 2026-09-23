// frontend/pages/homepage.test.ts
// Unit tests for the pure line-building logic behind the home page's
// service-outage banner (SHELL-02). See homepage.ts's own header comment for
// why this is automatic (driven by GET /status) rather than production's
// hand-edited updates.markdown notice.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { unavailableFeatureLines } from './homepage'

const ALL_OK: Record<string, string> = {
  peak_browser: 'ok',
  enrichment_analysis: 'ok',
  diff_analysis: 'ok',
  target_genes: 'ok',
  colo: 'ok',
  search: 'ok',
}

test('unavailableFeatureLines: everything ok -> no lines', () => {
  assert.deepEqual(unavailableFeatureLines(ALL_OK), [])
})

test('unavailableFeatureLines: Enrichment Analysis "ok (backup)" counts as up, not down', () => {
  assert.deepEqual(unavailableFeatureLines({ ...ALL_OK, enrichment_analysis: 'ok (backup)' }), [])
})

test('unavailableFeatureLines: one feature down -> one line naming it', () => {
  assert.deepEqual(
    unavailableFeatureLines({ ...ALL_OK, diff_analysis: 'unavailable' }),
    ['Diff Analysis is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.'],
  )
})

test('unavailableFeatureLines: every known feature name renders correctly', () => {
  assert.deepEqual(unavailableFeatureLines({
    peak_browser: 'unavailable',
    enrichment_analysis: 'unavailable',
    diff_analysis: 'unavailable',
    target_genes: 'unavailable',
    colo: 'unavailable',
    search: 'unavailable',
  }), [
    'Peak Browser is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
    'Enrichment Analysis is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
    'Diff Analysis is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
    'Target Genes is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
    'Colocalization is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
    'Dataset Search is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
  ])
})

test('unavailableFeatureLines: multiple features down -> fixed order, not input key order', () => {
  const features: Record<string, string> = {
    search: 'unavailable',
    colo: 'unavailable',
    peak_browser: 'ok',
    enrichment_analysis: 'ok',
    diff_analysis: 'ok',
    target_genes: 'unavailable',
  }
  assert.deepEqual(unavailableFeatureLines(features), [
    'Target Genes is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
    'Colocalization is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
    'Dataset Search is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
  ])
})

test('unavailableFeatureLines: unknown feature keys are ignored', () => {
  assert.deepEqual(
    unavailableFeatureLines({ ...ALL_OK, some_future_feature: 'unavailable' }),
    [],
  )
})

test('unavailableFeatureLines: a feature key missing entirely is treated as ok, not thrown on', () => {
  assert.deepEqual(unavailableFeatureLines({ diff_analysis: 'unavailable' }), [
    'Diff Analysis is temporarily unavailable due to a backend server issue. We are sorry for the inconvenience.',
  ])
})
