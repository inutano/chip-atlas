#!/usr/bin/env bash
# Run the Ruby test suite in the prebuilt chip-atlas-test:local image.
# Build the image once with: bash script/dev/build-test-image.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec docker run --rm -v "$REPO":/app -w /app chip-atlas-test:local \
  bundle exec ruby -Itest -e 'Dir.glob("./test/**/*_test.rb").sort.each { |f| require f }' \
  2>&1 | grep -vE "warning: already initialized constant|warning: previous definition of"
