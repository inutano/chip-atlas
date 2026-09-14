#!/usr/bin/env bash
# Build the test image used by script/dev/test.sh. Re-run after changing the Gemfile.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$REPO/Gemfile" "$REPO/Gemfile.lock" "$TMP/"
cat > "$TMP/Dockerfile" <<'DOCKER'
FROM ruby:4.0.5-slim
RUN apt-get update -qq && apt-get install -y -qq build-essential libsqlite3-dev git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
ENV BUNDLE_APP_CONFIG=/usr/local/bundle
RUN bundle install
DOCKER
docker build -t chip-atlas-test:local "$TMP"
