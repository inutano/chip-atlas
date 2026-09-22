#!/usr/bin/env bash
# Run the Ruby test suite in the prebuilt chip-atlas-test:local image.
# Build the image once with: bash script/dev/build-test-image.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The -e program below loads every test file and then, before Minitest runs,
# fails if any Minitest::Test subclass has a *private* method named test_*.
# Minitest collects public instance methods only, so a test written below a
# `private` keyword is skipped in complete silence -- the suite stays green
# and the run count simply does not move. That has now happened once here
# (four WabiService status tests), and it is the same shape as the six
# "passes while testing nothing" defects recorded in the post-parity outcome
# doc, so it gets a guard rather than a reminder to be careful.
exec docker run --rm --network none -v "$REPO":/app -w /app chip-atlas-test:local \
  bundle exec ruby -Itest -e '
    Dir.glob("./test/**/*_test.rb").sort.each { |f| require f }
    hidden = Minitest::Runnable.runnables.flat_map { |k|
      k.private_instance_methods(false).grep(/\Atest_/).map { |m| "#{k}##{m}" }
    }.sort
    unless hidden.empty?
      warn "ERROR: #{hidden.size} test method(s) are private and will never run:"
      hidden.each { |n| warn "  #{n}" }
      warn "Move them above the `private` keyword in their class."
      exit 1
    end
  ' \
  2>&1 | grep -vE "warning: already initialized constant|warning: previous definition of"
