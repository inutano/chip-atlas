#!/usr/bin/env bash
# UI parity checklist: how many production structural markers the local app has.
# Usage: bash script/dev/ui-checklist.sh [BASE_URL]
# Always exits 0 - this is a metric, not a gate.
set -uo pipefail
BASE="${1:-http://localhost:9292}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKERS="$DIR/parity-markers.txt"

if ! curl -sf -o /dev/null -m 5 "$BASE/health"; then
  echo "App not reachable at $BASE - start it with: bash ~/run/chip-atlas-local.sh"
  exit 0
fi

pass=0; total=0; cache_path=""; cache_body=""
while IFS=$'\t' read -r path desc needle; do
  [ -z "${path:-}" ] && continue
  case "$path" in \#*) continue ;; esac
  total=$((total + 1))
  if [ "$path" != "$cache_path" ]; then
    cache_body="$(curl -s -m 20 "$BASE$path")"
    cache_path="$path"
  fi
  if printf '%s' "$cache_body" | grep -qF -- "$needle"; then
    pass=$((pass + 1)); printf '  PASS  %-45s %s\n' "$desc" "$path"
  else
    printf '  FAIL  %-45s %s\n' "$desc" "$path"
  fi
done < "$MARKERS"

echo
echo "SCORE: $pass/$total"
exit 0
