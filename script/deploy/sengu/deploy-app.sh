#!/usr/bin/env bash
# deploy-app.sh — Deploy (or re-deploy) the ChIP-Atlas app to a provisioned instance.
#
# Usage (from the local dev machine):
#   ./deploy-app.sh <instance-ip> [--db path/to/database.sqlite]
#
# What it does:
#   1. Sync JS bundles from local public/js/ to the instance
#   2. Optionally upload the SQLite database
#   3. Write config/chip-atlas.env with the instance's public IP
#   4. Run database migrations
#   5. Start (or restart) the Puma service
#   6. Verify /health
#
# Prerequisites:
#   - Instance already provisioned (provision.sh completed)
#   - SSH key accessible (~/.ssh/chipatlas-202406.pem or configured in ~/.ssh/config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# ── Parse arguments ─────────────────────────────────────────────────────────
IP=""
DB_PATH=""
SSH_KEY="${CHIP_ATLAS_SSH_KEY:-$HOME/.ssh/chipatlas-202406.pem}"
SSH_USER="${CHIP_ATLAS_SSH_USER:-ec2-user}"
APP_DIR="/home/$SSH_USER/chip-atlas"

usage() {
  echo "Usage: $0 <instance-ip> [--db path/to/database.sqlite]"
  echo "  --db   Upload this SQLite file as the app database"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --db) DB_PATH="$2"; shift 2 ;;
    --help|-h) usage ;;
    -*) echo "Unknown option: $1"; usage ;;
    *) IP="$1"; shift ;;
  esac
done

[[ -n "$IP" ]] || usage

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
if [[ -f "$SSH_KEY" ]]; then
  SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

remote() { ssh $SSH_OPTS "$SSH_USER@$IP" "$@"; }
rsync_to() { rsync -az --partial -e "ssh $SSH_OPTS" "$@"; }

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# ── 1. Sync JS bundles ─────────────────────────────────────────────────────
log "Syncing JS bundles..."
rsync_to "$REPO_ROOT/public/js/" "$SSH_USER@$IP:$APP_DIR/public/js/"
log "  $(ls "$REPO_ROOT/public/js/"*.js 2>/dev/null | wc -l | tr -d ' ') JS files synced"

# ── 2. Upload database (optional) ──────────────────────────────────────────
if [[ -n "$DB_PATH" ]]; then
  if [[ ! -f "$DB_PATH" ]]; then
    echo "ERROR: Database file not found: $DB_PATH"
    exit 1
  fi
  DB_SIZE=$(du -h "$DB_PATH" | cut -f1)
  log "Uploading database ($DB_SIZE)... this may take a few minutes."
  rsync_to "$DB_PATH" "$SSH_USER@$IP:$APP_DIR/database.sqlite"
  log "  Upload complete"
fi

# ── 3. Write config/chip-atlas.env ──────────────────────────────────────────
log "Writing config/chip-atlas.env..."
remote "mkdir -p $APP_DIR/config && cat > $APP_DIR/config/chip-atlas.env" <<EOF
DATABASE_URL=sqlite://database.sqlite
CHIP_ATLAS_PERMITTED_HOSTS=.chip-atlas.org,$IP
WEB_CONCURRENCY=2
MAX_THREADS=5
PORT=9292
EOF
log "  CHIP_ATLAS_PERMITTED_HOSTS=.chip-atlas.org,$IP"

# ── 4. Run database migrations ─────────────────────────────────────────────
log "Running database migrations..."
remote "cd $APP_DIR && export PATH=\"\$HOME/.rbenv/shims:\$HOME/.rbenv/bin:\$PATH\" && RACK_ENV=production bundle exec rake db:migrate"

# ── 5. Start or restart Puma ───────────────────────────────────────────────
log "Starting Puma..."
remote "sudo systemctl restart chip-atlas-puma"

# ── 6. Verify health ───────────────────────────────────────────────────────
log "Waiting for /health..."
for i in $(seq 1 30); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "http://$IP/health" 2>/dev/null || echo "000")
  if [[ "$CODE" == "200" ]]; then
    log "Health check passed!"
    BODY=$(curl -s -m 10 "http://$IP/health")
    log "  $BODY"
    echo ""
    log "App is live at http://$IP/"
    exit 0
  fi
  sleep 2
done

echo "ERROR: Health check did not pass after 60 seconds"
echo "Debug: ssh $SSH_OPTS $SSH_USER@$IP 'sudo journalctl -u chip-atlas-puma -n 30 --no-pager'"
exit 1
