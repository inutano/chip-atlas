#!/bin/bash
# Build the app image (Ruby 3.2.2, as in production), boot it on a fresh
# database and run the smoke test. Needs only Docker and curl on the host.
#   bash script/test/docker-smoke.sh [host_port]     (default 9292)
set -u
cd "$(dirname "$0")/../.."
port=${1:-9292}
name=chip-atlas-smoke-$$

docker build -q -t chip-atlas-dev . || exit 1
docker run -d --rm --name "$name" -p "127.0.0.1:$port:9292" chip-atlas-dev \
  bash -c "bundle exec rake db:migrate && exec bundle exec rackup --host 0.0.0.0 -p 9292" >/dev/null || exit 1

bash script/test/smoke.sh "http://localhost:$port"
rc=$?
if [ $rc -ne 0 ]; then
  echo "--- app log ---"
  docker logs "$name" 2>&1 | tail -50
fi
docker stop "$name" >/dev/null 2>&1
exit $rc
