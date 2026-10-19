#!/usr/bin/env bash
# launch.sh — Launch a fresh Amazon Linux 2023 instance and provision it for ChIP-Atlas.
#
# Usage:
#   ./launch.sh [--arch arm64|x86_64] [--type INSTANCE_TYPE] [--db path/to/database.sqlite]
#
# Defaults:
#   --arch arm64      (Graviton — ~20% cheaper, native gems via Gemfile.lock)
#   --type t4g.medium (2 vCPU, 4 GB; override with --type for x86_64, e.g. t3.medium)
#   --db              (optional) upload a pre-built SQLite database
#
# What it does:
#   1. Find the latest Amazon Linux 2023 AMI for the chosen architecture
#   2. Launch an EC2 instance (reuses the project's key pair and security group)
#   3. Wait for SSH
#   4. Push and run provision.sh on the instance
#   5. Run deploy-app.sh to ship JS bundles, DB, env, and start the service
#   6. Verify health and print the access URL
#
# Prerequisites:
#   - AWS CLI configured (profile chip-atlas-launcher, region ap-northeast-1)
#   - SSH key at ~/.ssh/chipatlas-202406.pem
#   - JS bundles built locally (npm run build)
#   - Optionally: a pre-built database.sqlite to upload
#
# The instance is NOT registered in the ALB — it is reachable by direct IP only.
# To register in the ALB, use the existing script/deploy/deploy.sh workflow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TIMESTAMP="$(date +'%Y%m%d-%H%M%S')"

# ── Defaults ────────────────────────────────────────────────────────────────
ARCH="arm64"
INSTANCE_TYPE="t4g.medium"
DB_PATH=""
SSH_KEY="${CHIP_ATLAS_SSH_KEY:-$HOME/.ssh/chipatlas-202406.pem}"
SSH_USER="ec2-user"
BRANCH="sengu"

# AWS settings (same as existing launch-chip-atlas.conf)
AWS_PROFILE="${CHIP_ATLAS_AWS_PROFILE:-chip-atlas-launcher}"
AWS_REGION="${CHIP_ATLAS_AWS_REGION:-ap-northeast-1}"
KEY_NAME="chipatlas-202406"
SECURITY_GROUP="sg-065b702c2d8b5c432"
SUBNET_ID="subnet-0eaf6ab9177a579d2"   # VPC vpc-051247e2e78c5bd60, ap-northeast-1a
VOLUME_SIZE=32   # GB, gp3

# ── Parse arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --arch) ARCH="$2"; shift 2 ;;
    --type) INSTANCE_TYPE="$2"; shift 2 ;;
    --db)   DB_PATH="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,/^set /{ /^#/s/^# \?//p }' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
if [[ -f "$SSH_KEY" ]]; then
  SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

log() { echo "[$(date +'%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Validate ────────────────────────────────────────────────────────────────
[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"
aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1 \
  || die "AWS credentials not valid for profile $AWS_PROFILE"
[[ -n "$DB_PATH" && ! -f "$DB_PATH" ]] && die "Database file not found: $DB_PATH"

# ── 1. Find latest Amazon Linux 2023 AMI ────────────────────────────────────
log "Finding latest Amazon Linux 2023 AMI (arch=$ARCH)..."

AMI_ID=$(aws ec2 describe-images \
  --profile "$AWS_PROFILE" \
  --owners amazon \
  --filters \
    "Name=name,Values=al2023-ami-2*-kernel-*-$ARCH" \
    "Name=state,Values=available" \
    "Name=architecture,Values=$ARCH" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

[[ "$AMI_ID" == "None" || -z "$AMI_ID" ]] && die "No Amazon Linux 2023 AMI found for $ARCH"
AMI_NAME=$(aws ec2 describe-images --profile "$AWS_PROFILE" --image-ids "$AMI_ID" \
  --query 'Images[0].Name' --output text)
log "  AMI: $AMI_ID ($AMI_NAME)"

# ── 2. Launch instance ──────────────────────────────────────────────────────
INSTANCE_NAME="chip-atlas-sengu-$TIMESTAMP"
INFO_DIR="${CHIP_ATLAS_INFO_DIR:-/tmp}"
INFO_FILE="$INFO_DIR/${INSTANCE_NAME}_info.json"

log "Launching $INSTANCE_TYPE instance ($ARCH)..."

aws ec2 run-instances \
  --profile "$AWS_PROFILE" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SECURITY_GROUP" \
  --subnet-id "$SUBNET_ID" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Project,Value=chip-atlas},{Key=Branch,Value=$BRANCH}]" \
  --count 1 \
  > "$INFO_FILE"

INSTANCE_ID=$(jq -r '.Instances[0].InstanceId' "$INFO_FILE")
log "  Instance: $INSTANCE_ID (Name: $INSTANCE_NAME)"
log "  Info saved to: $INFO_FILE"

# Wait for public IP
log "Waiting for public IP..."
for i in $(seq 1 60); do
  PUBLIC_IP=$(aws ec2 describe-instances --profile "$AWS_PROFILE" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || echo "None")
  [[ "$PUBLIC_IP" != "None" && -n "$PUBLIC_IP" ]] && break
  sleep 5
done
[[ "$PUBLIC_IP" == "None" || -z "$PUBLIC_IP" ]] && die "No public IP assigned after 5 minutes"
log "  Public IP: $PUBLIC_IP"

# ── 3. Wait for SSH ─────────────────────────────────────────────────────────
log "Waiting for SSH..."
for i in $(seq 1 60); do
  if ssh $SSH_OPTS -o ConnectTimeout=5 "$SSH_USER@$PUBLIC_IP" "echo ok" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
ssh $SSH_OPTS -o ConnectTimeout=5 "$SSH_USER@$PUBLIC_IP" "echo ok" >/dev/null 2>&1 \
  || die "SSH not available after 5 minutes"
log "  SSH ready"

# ── 4. Provision ────────────────────────────────────────────────────────────
log "Uploading config files and provision.sh..."
scp $SSH_OPTS \
  "$SCRIPT_DIR/provision.sh" \
  "$SCRIPT_DIR/chip-atlas.nginx.conf" \
  "$SCRIPT_DIR/chip-atlas-puma.service" \
  "$SSH_USER@$PUBLIC_IP:~/"
ssh $SSH_OPTS "$SSH_USER@$PUBLIC_IP" \
  "chmod +x ~/provision.sh && CHIP_ATLAS_BRANCH=$BRANCH CHIP_ATLAS_RUBY_VERSION=4.0.5 bash ~/provision.sh 2>&1" \
  | tee "$INFO_DIR/${INSTANCE_NAME}_provision.log"

# ── 5. Deploy app ──────────────────────────────────────────────────────────
log "Running deploy-app.sh..."
DEPLOY_ARGS="$PUBLIC_IP"
[[ -n "$DB_PATH" ]] && DEPLOY_ARGS="$DEPLOY_ARGS --db $DB_PATH"

CHIP_ATLAS_SSH_KEY="$SSH_KEY" CHIP_ATLAS_SSH_USER="$SSH_USER" \
  bash "$SCRIPT_DIR/deploy-app.sh" $DEPLOY_ARGS

# ── 6. Summary ──────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " ChIP-Atlas deployed successfully"
echo "========================================"
echo " URL:       http://$PUBLIC_IP/"
echo " Instance:  $INSTANCE_ID ($INSTANCE_TYPE, $ARCH)"
echo " AMI:       $AMI_ID ($AMI_NAME)"
echo " Name:      $INSTANCE_NAME"
echo " Branch:    $BRANCH"
echo " Region:    $AWS_REGION"
echo ""
echo " SSH:       ssh $SSH_OPTS $SSH_USER@$PUBLIC_IP"
echo ""
echo " Stop:      aws ec2 stop-instances --profile $AWS_PROFILE --region $AWS_REGION --instance-ids $INSTANCE_ID"
echo " Terminate: aws ec2 terminate-instances --profile $AWS_PROFILE --region $AWS_REGION --instance-ids $INSTANCE_ID"
echo " Re-deploy: cd $SCRIPT_DIR && ./deploy-app.sh $PUBLIC_IP [--db path/to/db]"
echo ""
echo " Cost: $INSTANCE_TYPE ~\$0.034/hr (Graviton) or ~\$0.042/hr (x86_64)"
echo " Note: Public IP changes on stop/start (not an Elastic IP)"
echo "========================================"
