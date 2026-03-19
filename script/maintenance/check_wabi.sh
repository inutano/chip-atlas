#!/bin/bash
#
# WABI API Smoke Test for ChIP-Atlas
#
# Checks that the WABI backend at DDBJ NIG supercomputer is operational:
#   1. Health endpoint returns "chipatlas"
#   2. Enrichment analysis job submission succeeds
#   3. Job completes within timeout
#   4. Results are retrievable
#
# Usage: ./check_wabi.sh [-t TIMEOUT] [-q]
#   -t TIMEOUT  Max seconds to wait for job completion (default: 600)
#   -q          Quiet mode — only print failures and final status

WABI_ENDPOINT="https://dtn1.ddbj.nig.ac.jp/wabi/chipatlas/"
POLL_INTERVAL=15
TIMEOUT=600
QUIET=false

usage() {
  echo "Usage: $0 [-t TIMEOUT] [-q]"
  echo "  -t TIMEOUT  Max seconds to wait for job completion (default: 600)"
  echo "  -q          Quiet mode"
  exit 1
}

while getopts "t:qh" opt; do
  case "$opt" in
    t) TIMEOUT="$OPTARG" ;;
    q) QUIET=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

PASS=0
FAIL=0

log() {
  if [ "$QUIET" = false ]; then
    echo "$@"
  fi
}

pass() {
  PASS=$((PASS + 1))
  log "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1" >&2
}

# ---------- Step 1: Health check ----------
log "Step 1: Health endpoint check"

HEALTH_RESPONSE=$(curl -s -f -m 10 "$WABI_ENDPOINT" 2>/dev/null)
HEALTH_STATUS=$?

if [ $HEALTH_STATUS -ne 0 ]; then
  fail "Health endpoint unreachable (curl exit $HEALTH_STATUS)"
elif [ "$HEALTH_RESPONSE" != "chipatlas" ]; then
  fail "Health endpoint returned unexpected response: '$HEALTH_RESPONSE'"
else
  pass "Health endpoint returned 'chipatlas'"
fi

# Bail early if health check failed — no point submitting jobs
if [ $FAIL -gt 0 ]; then
  echo ""
  echo "RESULT: $PASS passed, $FAIL failed — WABI is DOWN"
  exit 1
fi

# ---------- Step 2: Submit enrichment analysis job ----------
log "Step 2: Submit enrichment analysis job"

SUBMIT_RESPONSE=$(curl -s -f -m 30 -X POST \
  -d "address=" \
  -d "format=text" \
  -d "result=www" \
  -d "genome=hg38" \
  -d "antigenClass=Histone" \
  -d "cellClass=Blood" \
  -d "threshold=50" \
  -d "typeA=bed" \
  -d "bedAFile=chr1	1000000	2000000" \
  -d "typeB=rnd" \
  -d "bedBFile=empty" \
  -d "permTime=1" \
  -d "title=wabi_smoke_test" \
  -d "descriptionA=smoke_test" \
  -d "descriptionB=random" \
  -d "distanceUp=5000" \
  -d "distanceDown=5000" \
  "$WABI_ENDPOINT" 2>/dev/null)

REQUEST_ID=$(echo "$SUBMIT_RESPONSE" | grep '^requestId:' | awk '{print $2}')

if [ -z "$REQUEST_ID" ]; then
  fail "Job submission failed — no requestId in response"
  echo "$SUBMIT_RESPONSE" >&2
  echo ""
  echo "RESULT: $PASS passed, $FAIL failed — WABI job submission BROKEN"
  exit 1
else
  pass "Job submitted: $REQUEST_ID"
fi

# ---------- Step 3: Poll for completion ----------
log "Step 3: Wait for job completion (timeout: ${TIMEOUT}s)"

ELAPSED=0
JOB_STATUS="unknown"

while [ $ELAPSED -lt $TIMEOUT ]; do
  sleep $POLL_INTERVAL
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  STATUS_RESPONSE=$(curl -s -f -m 10 \
    "${WABI_ENDPOINT}${REQUEST_ID}?info=status&format=text" 2>/dev/null)

  JOB_STATUS=$(echo "$STATUS_RESPONSE" | grep '^status:' | awk '{print $2}')

  if [ "$JOB_STATUS" = "finished" ]; then
    break
  fi

  log "  ... $JOB_STATUS (${ELAPSED}s elapsed)"
done

if [ "$JOB_STATUS" = "finished" ]; then
  # Check SLURM exit status
  SLURM_STATUS=$(echo "$STATUS_RESPONSE" | grep 'COMPLETED')
  if [ -n "$SLURM_STATUS" ]; then
    pass "Job completed successfully in ${ELAPSED}s"
  else
    fail "Job finished but SLURM status is not COMPLETED"
    echo "$STATUS_RESPONSE" >&2
  fi
else
  fail "Job did not finish within ${TIMEOUT}s (last status: $JOB_STATUS)"
  echo ""
  echo "RESULT: $PASS passed, $FAIL failed — WABI job execution BROKEN"
  exit 1
fi

# ---------- Step 4: Verify result retrieval ----------
log "Step 4: Verify result retrieval"

# Check TSV results
TSV_RESULT=$(curl -s -f -m 30 \
  "${WABI_ENDPOINT}${REQUEST_ID}?info=result&format=tsv" 2>/dev/null)

if [ -z "$TSV_RESULT" ]; then
  fail "TSV result is empty"
elif echo "$TSV_RESULT" | grep -q '^\[ERROR\]'; then
  fail "TSV result contains error: $(echo "$TSV_RESULT" | head -1)"
else
  LINE_COUNT=$(echo "$TSV_RESULT" | wc -l | tr -d ' ')
  pass "TSV result retrieved ($LINE_COUNT lines)"
fi

# Check log
LOG_RESULT=$(curl -s -f -m 30 \
  "${WABI_ENDPOINT}${REQUEST_ID}?info=result&format=log" 2>/dev/null)

if [ -z "$LOG_RESULT" ]; then
  fail "Log result is empty"
elif echo "$LOG_RESULT" | grep -q '^\[ERROR\]'; then
  fail "Log contains error: $(echo "$LOG_RESULT" | grep '^\[ERROR\]' | head -1)"
else
  pass "Log retrieved without errors"
fi

# ---------- Summary ----------
echo ""
if [ $FAIL -eq 0 ]; then
  echo "RESULT: $PASS passed, $FAIL failed — WABI is UP"
  exit 0
else
  echo "RESULT: $PASS passed, $FAIL failed — WABI has ISSUES"
  exit 1
fi
