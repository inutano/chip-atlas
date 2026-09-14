#!/usr/bin/env bash
# Side-by-side screenshots of production vs the local app.
# Usage: bash script/dev/ui-parity.sh [BASE_URL]
set -euo pipefail
BASE="${1:-http://localhost:9292}"
OLD="https://chip-atlas.org"
OUT="tmp/ui-parity/$(date +'%Y%m%d-%H%M%S')"
mkdir -p "$OUT"

PAGES="/ /peak_browser /search /colo /target_genes /enrichment_analysis /diff_analysis"
VIEW="/view?id=SRX019491"

shoot () { # url outfile
  chromium --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --window-size=1440,1600 --virtual-time-budget=10000 \
    --screenshot="$2" "$1" >/dev/null 2>&1 || true
}

for p in $PAGES "$VIEW"; do
  name="$(printf '%s' "$p" | tr -c 'A-Za-z0-9' '_')"
  shoot "$OLD$p"  "$OUT/${name}_old.png"
  shoot "$BASE$p" "$OUT/${name}_new.png"
  if [ -f "$OUT/${name}_old.png" ] && [ -f "$OUT/${name}_new.png" ]; then
    magick "$OUT/${name}_old.png" "$OUT/${name}_new.png" +append "$OUT/${name}_sheet.png"
    rm -f "$OUT/${name}_old.png" "$OUT/${name}_new.png"
    echo "  $OUT/${name}_sheet.png"
  fi
done

echo "Contact sheets in $OUT (left = production, right = local)"
