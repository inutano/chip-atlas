// esbuild.config.mjs
import * as esbuild from 'esbuild'
import { readdirSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))

// Auto-discover page entry points from frontend/pages/*.ts
const pageFiles = readdirSync(join(__dirname, 'frontend/pages'))
  .filter(f => f.endsWith('.ts') && !f.includes('.test.') && !f.includes('.spec.'))
  .map(f => join(__dirname, 'frontend/pages', f))

const isWatch = process.argv.includes('--watch')

const buildOptions = {
  entryPoints: pageFiles,
  bundle: true,
  outdir: join(__dirname, 'public/js'),
  format: 'esm',
  target: ['es2020'],
  minify: process.env.NODE_ENV === 'production',
  sourcemap: process.env.NODE_ENV !== 'production',
  logLevel: 'info',
}

if (isWatch) {
  const ctx = await esbuild.context(buildOptions)
  await ctx.watch()
  console.log('Watching for changes...')
} else {
  await esbuild.build(buildOptions)
}
