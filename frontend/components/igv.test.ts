// frontend/components/igv.test.ts
// Unit tests for igvGenomeParam: the owner's report is that IGV desktop has
// no bundled TAIR12 genome, so a bare genome code (genome=TAIR12) in IGV's
// /load command URL silently fails to resolve. Every assembly's genome=
// value must instead be the genome's own JSON URL
// (https://chip-atlas.dbcls.jp/data/genome/<g>/<g>.json) - which is also
// that JSON's own `id` field - uniformly across all seven bundled genomes,
// not just TAIR12. See SCRATCH/investigation/igv.md.
//
// Run with: bash script/dev/test-frontend.sh

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { igvGenomeParam } from './igv'

test('igvGenomeParam: hg38 resolves to its own genome JSON URL', () => {
  assert.equal(igvGenomeParam('hg38'), 'https://chip-atlas.dbcls.jp/data/genome/hg38/hg38.json')
})

test('igvGenomeParam: TAIR12 resolves to its own genome JSON URL (the owner-reported defect)', () => {
  assert.equal(igvGenomeParam('TAIR12'), 'https://chip-atlas.dbcls.jp/data/genome/TAIR12/TAIR12.json')
})
