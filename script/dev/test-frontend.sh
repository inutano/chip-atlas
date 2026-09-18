#!/usr/bin/env bash
# Runs the frontend's pure-logic unit tests (*.test.ts under frontend/) with
# Node's built-in test runner.
#
# Tests are compiled with esbuild first rather than run as raw .ts, because
# this codebase uses TS parameter properties (frontend/api/client.ts's
# ApiError) that Node's own --experimental-strip-types cannot handle without
# a real transform. esbuild is already this project's bundler (see
# esbuild.config.mjs) — reusing it here avoids adding a test-only dependency
# just to work around that gap.
#
# Usage: bash script/dev/test-frontend.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"

TEST_FILES=$(find frontend -name '*.test.ts' -o -name '*.spec.ts')
if [ -z "$TEST_FILES" ]; then
  echo "No frontend *.test.ts files found."
  exit 0
fi
TEST_FILE_COUNT=$(printf '%s\n' "$TEST_FILES" | grep -c .)

OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

# shellcheck disable=SC2086
node_modules/.bin/esbuild $TEST_FILES \
  --bundle --platform=node --format=esm --target=node18 \
  --outdir="$OUT_DIR" >/dev/null

# esbuild preserves each test file's path below the lowest common ancestor
# of all entry points (e.g. pages/*.js, components/*.js once tests exist in
# more than one frontend/ subdirectory), so the compiled files are not all
# directly under $OUT_DIR. Enumerate them recursively rather than globbing
# "$OUT_DIR"/*.js, which would silently match nothing and report a false
# "0 tests" pass.
mapfile -t COMPILED_TESTS < <(find "$OUT_DIR" -name '*.js')

# `node --test` with zero targets (an empty "${COMPILED_TESTS[@]}" expansion)
# reports "tests 0 / pass 0 / fail 0" and exits 0 — a runner that claims
# success while running nothing is exactly the false-green defect the
# recursive find above was meant to fix, just one layer up. We already know
# $TEST_FILE_COUNT source test files exist (checked above), so an empty or
# short compiled list here is a real build failure, not "no tests to run" —
# fail loudly instead of silently reporting green.
if [ "${#COMPILED_TESTS[@]}" -eq 0 ]; then
  echo "ERROR: found $TEST_FILE_COUNT frontend test source file(s) but 0 compiled .js files under $OUT_DIR — the esbuild step produced nothing to run. Refusing to report a false green." >&2
  exit 1
fi
if [ "${#COMPILED_TESTS[@]}" -ne "$TEST_FILE_COUNT" ]; then
  echo "ERROR: expected $TEST_FILE_COUNT compiled test file(s) (one per frontend/**/*.test.ts), found ${#COMPILED_TESTS[@]} under $OUT_DIR." >&2
  exit 1
fi

node --test "${COMPILED_TESTS[@]}"
