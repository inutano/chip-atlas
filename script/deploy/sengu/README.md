# ChIP-Atlas Sengu Deployment Scripts

Launch and provision a clean Amazon Linux 2023 instance for the sengu-branch
ChIP-Atlas app. Designed for quick test deployments — one command from the
dev machine to a running instance.

## Quick start

```bash
# Build JS bundles first (if not already built)
npm run build

# Launch a new instance and deploy (ARM/Graviton, t4g.medium)
cd script/deploy/sengu
./launch.sh --db /path/to/database.sqlite

# Or deploy to an already-provisioned instance
./deploy-app.sh 1.2.3.4 --db /path/to/database.sqlite
```

## Scripts

| Script | Where it runs | Purpose |
|--------|--------------|---------|
| `launch.sh` | Local (Mac) | Find AMI, launch EC2, push provision.sh, run deploy-app.sh |
| `provision.sh` | EC2 instance | Install packages, rbenv, Ruby, clone repo, set up nginx + systemd |
| `deploy-app.sh` | Local (Mac) | Sync JS bundles, upload DB, write env, migrate, start Puma, verify |

## Configuration files

| File | Purpose |
|------|---------|
| `chip-atlas-puma.service` | systemd unit for Puma |
| `chip-atlas.nginx.conf` | nginx site config |
| `chip-atlas.env.example` | Template for env vars |

## Architecture choices

- **Amazon Linux 2023** — latest OS with long-term support (through 2028),
  dnf-based, modern kernel.
- **ARM (Graviton) by default** — `t4g.medium` is ~20% cheaper than
  `t3.medium` for equivalent compute. The Gemfile.lock already has
  `aarch64-linux` platforms, so native gems (sqlite3) install without
  compilation. Pass `--arch x86_64 --type t3.medium` to override.
- **nginx + Puma** — nginx serves static assets directly (JS/CSS/images),
  proxies dynamic requests to Puma over HTTP (localhost:9292). Keepalive
  connections reduce per-request overhead.
- **systemd** — native process management with restart-on-failure, journal
  logging, and security hardening (NoNewPrivileges, ProtectSystem=strict).
- **rbenv** — isolated Ruby installation; no interference with system
  packages.
- **SQLite** — the database file is uploaded from the dev machine (pre-built
  with `rake metadata:load`). This avoids the 10+ minute metadata download
  and load on the instance.

## Instance lifecycle

```bash
# Check status
aws ec2 describe-instances --profile chip-atlas-launcher --region ap-northeast-1 \
  --filters "Name=tag:Project,Values=chip-atlas" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,IP:PublicIpAddress,Type:InstanceType}' \
  --output table

# Stop (preserves data; public IP will change on restart)
aws ec2 stop-instances --profile chip-atlas-launcher --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXXXXXXXXX

# Start
aws ec2 start-instances --profile chip-atlas-launcher --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXXXXXXXXX
# Then update CHIP_ATLAS_PERMITTED_HOSTS with the new IP

# Terminate (deletes everything)
aws ec2 terminate-instances --profile chip-atlas-launcher --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXXXXXXXXX
```

## Re-deploying after a code change

```bash
# On the dev machine: rebuild JS, then deploy
npm run build
cd script/deploy/sengu
./deploy-app.sh <instance-ip>
# (Omit --db to keep the existing database)
```

## SSH access

```bash
ssh -i ~/.ssh/chipatlas-202406.pem ec2-user@<instance-ip>

# View app logs
sudo journalctl -u chip-atlas-puma -f

# View nginx logs
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log

# Restart the app
sudo systemctl restart chip-atlas-puma
```

## Differences from the production (AMI-based) stack

| Aspect | Production (current) | Sengu (this) |
|--------|---------------------|--------------|
| OS | Ubuntu (AMI snapshot) | Amazon Linux 2023 (fresh) |
| Ruby | System / rbenv (varies) | rbenv, pinned to .ruby-version |
| App server | Unicorn (init.d) | Puma (systemd) |
| Reverse proxy | nginx (inline in nginx.conf) | nginx (conf.d drop-in) |
| Deploy | AMI snapshot + launch template | Git pull + rsync JS + restart |
| DB | Metadata loaded on instance | Pre-built DB uploaded from dev |
