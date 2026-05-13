// esbuild.config.mjs
import * as esbuild from 'esbuild'
import { readdirSync } from 'fs'

// Auto-discover page entry points from frontend/pages/*.ts
const pageFiles = readdirSync('frontend/pages')
  .filter(f => f.endsWith('.ts'))
  .map(f => `frontend/pages/${f}`)

const isWatch = process.argv.includes('--watch')

const buildOptions = {
  entryPoints: pageFiles,
  bundle: true,
  outdir: 'public/js',
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
