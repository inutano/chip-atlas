#!/bin/bash
#
# ChIP-Atlas Smoke Test
#
# Tests all major endpoints and form submissions against a running instance.
#
# Usage: ./smoke_test.sh [BASE_URL]
#   BASE_URL defaults to http://localhost:9292

BASE_URL="${1:-http://localhost:9292}"
PASS=0
FAIL=0
WABI_REQUEST_ID=""

# ---- Helpers ----

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1" >&2
}

# Test GET endpoint returns expected HTTP status
test_get() {
  local name="$1"
  local path="$2"
  local expected_status="${3:-200}"

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -m 30 "${BASE_URL}${path}")
  if [ "$status" = "$expected_status" ]; then
    pass "$name (HTTP $status)"
  else
    fail "$name — expected HTTP $expected_status, got $status"
  fi
}

# Test GET endpoint returns expected body content
test_get_body() {
  local name="$1"
  local path="$2"
  local expected="$3"

  local body
  body=$(curl -s -m 30 "${BASE_URL}${path}")
  if echo "$body" | grep -q "$expected"; then
    pass "$name"
  else
    fail "$name — expected body to contain '$expected', got: $(echo "$body" | head -1)"
  fi
}

# Test POST endpoint with JSON body
test_post_json() {
  local name="$1"
  local path="$2"
  local json="$3"
  local expected="$4"

  local body
  body=$(curl -s -m 30 -X POST -H "Content-Type: application/json" -d "$json" "${BASE_URL}${path}")
  if echo "$body" | grep -q "$expected"; then
    pass "$name"
  else
    fail "$name — expected '$expected' in response, got: $(echo "$body" | head -1)"
  fi
}

# ---- Tests ----

echo "=== ChIP-Atlas Smoke Test ==="
echo "Target: $BASE_URL"
echo ""

# 1. Pages
echo "Step 1: Page endpoints"
test_get "Top page" "/"
test_get "Health" "/health"
test_get "Peak browser" "/peak_browser"
test_get "Colocalization" "/colo"
test_get "Target genes" "/target_genes"
test_get "Enrichment analysis" "/enrichment_analysis"
test_get "Diff analysis" "/diff_analysis"
test_get "Publications" "/publications"
echo ""

# 2. WABI endpoint status
echo "Step 2: WABI endpoint status"
test_get_body "WABI status returns chipatlas" "/wabi_endpoint_status" "chipatlas"
echo ""

# 3. Data APIs
echo "Step 3: Data APIs"
test_get_body "Experiment types" "/data/experiment_types?genome=sacCer3" "Histone"
test_get_body "Sample types" "/data/sample_types?genome=sacCer3&agClass=Histone" "All cell types"
test_get_body "Chip antigen" "/data/chip_antigen?genome=sacCer3&agClass=Histone&clClass=All+cell+types" "H2A.Z"
test_get_body "Q-value range" "/qvalue_range" "50"
echo ""

# 4. FTS Search
echo "Step 4: Full-text search"
test_get_body "Search H3K4me3" "/search?q=H3K4me3" "experiments"
echo ""

# 5. Peak browser form
echo "Step 5: Peak browser (browse & download)"
BROWSE_JSON='{"condition":{"genome":"sacCer3","agClass":"Histone","agSubClass":"H2A.Z","clClass":"All cell types","threshold":"50"}}'
test_post_json "Browse" "/browse" "$BROWSE_JSON" "load?genome=sacCer3"
DOWNLOAD_JSON='{"condition":{"genome":"sacCer3","agClass":"Histone","agSubClass":"H2A.Z","clClass":"All cell types","clSubClass":"-","qval":"50"}}'
test_post_json "Download" "/download" "$DOWNLOAD_JSON" "chip-atlas.dbcls.jp/data"
echo ""

# 6. Colocalization
echo "Step 6: Colocalization"
COLO_JSON='{"condition":{"genome":"sacCer3","antigen":"H2A.Z","cellline":"All cell types"}}'
test_post_json "Colo submit" "/colo?type=submit" "$COLO_JSON" ".html"
test_post_json "Colo TSV" "/colo?type=tsv" "$COLO_JSON" ".tsv"
echo ""

# 7. Target genes
echo "Step 7: Target genes"
TG_JSON='{"condition":{"genome":"sacCer3","antigen":"H2A.Z","distance":"1000"}}'
test_post_json "Target genes submit" "/target_genes?type=submit" "$TG_JSON" ".html"
test_post_json "Target genes TSV" "/target_genes?type=tsv" "$TG_JSON" ".tsv"
echo ""

# 8. Enrichment analysis via WABI
echo "Step 8: Enrichment analysis (WABI job submission)"
EA_RESPONSE=$(curl -s -m 30 -X POST \
  -d "address=" \
  -d "format=text" \
  -d "result=www" \
  -d "genome=sacCer3" \
  -d "antigenClass=Histone" \
  -d "cellClass=All+cell+types" \
  -d "threshold=50" \
  -d "typeA=bed" \
  -d "bedAFile=chrI	1000	5000" \
  -d "typeB=rnd" \
  -d "bedBFile=empty" \
  -d "permTime=1" \
  -d "title=smoke_test" \
  -d "descriptionA=test" \
  -d "descriptionB=random" \
  -d "distanceUp=5000" \
  -d "distanceDown=5000" \
  "${BASE_URL}/wabi_chipatlas")

WABI_REQUEST_ID=$(echo "$EA_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['requestId'])" 2>/dev/null)

if [ -n "$WABI_REQUEST_ID" ]; then
  pass "EA job submitted: $WABI_REQUEST_ID"
else
  fail "EA job submission — no requestId in response: $EA_RESPONSE"
fi
echo ""

# 9. Poll WABI job
if [ -n "$WABI_REQUEST_ID" ]; then
  echo "Step 9: Poll WABI job (timeout: 600s)"
  ELAPSED=0
  POLL_INTERVAL=15
  TIMEOUT=600
  JOB_STATUS="unknown"

  while [ $ELAPSED -lt $TIMEOUT ]; do
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    JOB_STATUS=$(curl -s -m 10 "${BASE_URL}/wabi_chipatlas?id=${WABI_REQUEST_ID}")

    if [ "$JOB_STATUS" = "finished" ]; then
      break
    fi
    echo "  ... $JOB_STATUS (${ELAPSED}s elapsed)"
  done

  if [ "$JOB_STATUS" = "finished" ]; then
    pass "EA job completed in ${ELAPSED}s"
  else
    fail "EA job did not finish within ${TIMEOUT}s (last status: $JOB_STATUS)"
  fi
  echo ""
fi

# ---- Summary ----
echo "==============================="
if [ $FAIL -eq 0 ]; then
  echo "RESULT: $PASS passed, $FAIL failed — ALL OK"
  exit 0
else
  echo "RESULT: $PASS passed, $FAIL failed — ISSUES FOUND"
  exit 1
fi
