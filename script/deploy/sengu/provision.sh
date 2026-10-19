#!/usr/bin/env bash
# provision.sh — Bootstrap a fresh Amazon Linux 2023 instance for ChIP-Atlas.
#
# Runs as ec2-user on the target instance (pushed and invoked by launch.sh).
# Idempotent: safe to re-run if interrupted.
#
# What it does:
#   1. Install system packages (nginx, git, build tools, SQLite/OpenSSL/zlib/libyaml dev)
#   2. Install rbenv + ruby-build + Ruby (version from .ruby-version)
#   3. Clone the repo and install gems
#   4. Install the nginx site config and systemd service
#
# What it does NOT do (handled by deploy-app.sh):
#   - Copy the SQLite database
#   - Copy the JS bundles (they are gitignored; built on the dev machine)
#   - Write config/chip-atlas.env (contains instance-specific values)
#   - Start the Puma service
set -euo pipefail

REPO_URL="${CHIP_ATLAS_REPO_URL:-https://github.com/inutano/chip-atlas.git}"
BRANCH="${CHIP_ATLAS_BRANCH:-sengu}"
RUBY_VERSION="${CHIP_ATLAS_RUBY_VERSION:-4.0.5}"
APP_DIR="/home/ec2-user/chip-atlas"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# ─── 1. System packages ────────────────────────────────────────────────────
log "Installing system packages..."
sudo dnf update -y -q
sudo dnf install -y -q \
  nginx git gcc gcc-c++ make \
  openssl-devel readline-devel zlib-devel libyaml-devel \
  sqlite sqlite-devel libffi-devel \
  tar gzip bzip2 patch

# ─── 2. rbenv + ruby-build + Ruby ──────────────────────────────────────────
if [ ! -d "$HOME/.rbenv" ]; then
  log "Installing rbenv..."
  git clone --depth 1 https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
else
  log "rbenv already installed, updating..."
  (cd "$HOME/.rbenv" && git pull -q)
fi

if [ ! -d "$HOME/.rbenv/plugins/ruby-build" ]; then
  log "Installing ruby-build..."
  git clone --depth 1 https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build"
else
  log "ruby-build already installed, updating..."
  (cd "$HOME/.rbenv/plugins/ruby-build" && git pull -q)
fi

export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"

if rbenv versions --bare | grep -qx "$RUBY_VERSION"; then
  log "Ruby $RUBY_VERSION already installed"
else
  log "Building Ruby $RUBY_VERSION (this takes 3-5 minutes on t4g.medium)..."
  RUBY_CONFIGURE_OPTS="--disable-install-doc" rbenv install "$RUBY_VERSION"
fi
rbenv global "$RUBY_VERSION"
ruby -v

# ─── 3. Clone repo + install gems ──────────────────────────────────────────
if [ -d "$APP_DIR/.git" ]; then
  log "Repo exists, fetching and checking out $BRANCH..."
  cd "$APP_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  log "Cloning repo (branch $BRANCH)..."
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
fi

log "Installing gems (without dev/test)..."
gem install bundler --no-document 2>/dev/null || true
bundle config set --local deployment true
bundle config set --local without 'development test'
bundle install --jobs "$(nproc)"

# Create required directories
mkdir -p tmp/pids log

# ─── 4. nginx site ─────────────────────────────────────────────────────────
# Config files may come from the repo (if committed) or from ~/
# (SCP'd by launch.sh before provision.sh runs). Try the repo first.
NGINX_CONF="$APP_DIR/script/deploy/sengu/chip-atlas.nginx.conf"
PUMA_UNIT="$APP_DIR/script/deploy/sengu/chip-atlas-puma.service"
[[ -f "$NGINX_CONF" ]] || NGINX_CONF="$HOME/chip-atlas.nginx.conf"
[[ -f "$PUMA_UNIT" ]] || PUMA_UNIT="$HOME/chip-atlas-puma.service"

log "Configuring nginx..."
sudo cp "$NGINX_CONF" /etc/nginx/conf.d/chip-atlas.conf
sudo rm -f /etc/nginx/conf.d/default.conf
# Comment out AL2023's default server block to avoid conflict
sudo sed -i '/^    server {/,/^    }/s/^/#/' /etc/nginx/nginx.conf 2>/dev/null || true
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl start nginx || sudo systemctl reload nginx

# ─── 5. systemd service (installed but NOT started yet) ─────────────────────
log "Installing systemd service..."
sudo cp "$PUMA_UNIT" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable chip-atlas-puma
# Not started here — deploy-app.sh writes the env file and DB first.

log "Provision complete. Run deploy-app.sh next."
