#!/bin/bash
# Smoke test against a running app. Used by CI and by docker-smoke.sh.
#   bash script/test/smoke.sh [base_url]     (default http://localhost:9292)
base=${1:-http://localhost:9292}
failed=0

status() { curl -s -o /dev/null -m 20 -w "%{http_code}" "$@" || true; }

expect() { # expect <code> <label> <curl args...>
  local want=$1 label=$2; shift 2
  local got; got=$(status "$@")
  if [ "$got" = "$want" ]; then
    echo "OK:   $want $label"
  else
    echo "FAIL: got $got, expected $want: $label"
    failed=1
  fi
}

expect_remote() { # expect_remote <code> <url passed to /api/remoteUrlStatus>
  expect "$1" "remoteUrlStatus url='$2'" --get --data-urlencode "url=$2" "$base/api/remoteUrlStatus"
}

# Booting downloads the experiment lists and builds the search index,
# so wait for the port instead of sleeping a fixed time.
for _ in $(seq 1 60); do
  curl -s -o /dev/null -m 5 "$base/health" && break
  sleep 3
done

expect 200 "/health" "$base/health"
expect 200 "/" "$base/"

# /api/remoteUrlStatus must only ask the data storage
expect_remote 200 "https://chip-atlas.dbcls.jp/data/metadata/ExperimentList.json"
expect_remote 404 "https://chip-atlas.dbcls.jp/data/no-such-file"
expect_remote 400 "https://example.com/"
expect_remote 400 "http://169.254.169.254/latest/meta-data/"
expect_remote 400 "https://chip-atlas.dbcls.jp:22/"
expect_remote 400 "https://chip-atlas.dbcls.jp.example.com/data/x"
expect_remote 400 "file:///etc/passwd"
expect_remote 400 "http://["
expect_remote 400 ""

exit $failed
