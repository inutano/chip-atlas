#!/usr/bin/env bash
#
# Blue-green deployment for ChIP-Atlas
#
# Usage:
#   ./deploy.sh                          # Full deployment
#   ./deploy.sh --dry-run                # Read-only: validate everything, skip mutations
#   ./deploy.sh --skip-launch --instance-id i-xxx  # Re-provision existing instance
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP="$(date +'%Y%m%d-%H%M%S')"
LOG_FILE="${SCRIPT_DIR}/deploy-${TIMESTAMP}.log"
INSTANCE_INFO_FILE="${SCRIPT_DIR}/deploy-${TIMESTAMP}-instance.json"

# Defaults
DRY_RUN=false
SKIP_LAUNCH=false
TARGET_INSTANCE_ID=""

# SSH settings
SSH_USER="ubuntu"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
APP_DIR="/home/ubuntu/chip-atlas"

# Timeouts
SSH_WAIT_MAX=300      # 5 minutes
HEALTH_WAIT_MAX=300   # 5 minutes
DRAIN_WAIT=60         # 60 seconds for connection draining

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-launch)
            SKIP_LAUNCH=true
            shift
            ;;
        --instance-id)
            TARGET_INSTANCE_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging
log() {
    local msg="[$(date +'%H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_error() {
    log "ERROR: $*"
}

die() {
    log_error "$*"
    exit 1
}

# Load config
CONF_FILE="${SCRIPT_DIR}/deploy.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    die "Config file not found: $CONF_FILE (copy deploy.conf.example and fill in values)"
fi
# shellcheck source=/dev/null
source "$CONF_FILE"

# Validate required config vars
for var in AWS_EC2_LAUNCH_TEMPLATE_ID CHIP_ATLAS_AWS_ACCOUNT_ID ALB_TARGET_GROUP_ARN; do
    if [[ -z "${!var:-}" ]]; then
        die "Required config variable $var is not set in deploy.conf"
    fi
done

# SSH_KEY_FILE is optional (uses default SSH key if not set)
if [[ -n "${SSH_KEY_FILE:-}" ]]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY_FILE"
fi

# ─── Step 1: Validate AWS credentials ───────────────────────────────────────

validate_aws() {
    log "Step 1: Validating AWS credentials..."
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
        || die "Failed to get AWS caller identity. Are credentials configured?"

    if [[ "$account_id" != "$CHIP_ATLAS_AWS_ACCOUNT_ID" ]]; then
        die "AWS account mismatch: got $account_id, expected $CHIP_ATLAS_AWS_ACCOUNT_ID"
    fi
    log "  AWS account verified: $account_id"
}

# ─── Step 2: Get current instance in ALB ─────────────────────────────────────

get_current_instance() {
    log "Step 2: Finding current healthy instance in ALB target group..."
    local targets
    targets=$(aws elbv2 describe-target-health \
        --target-group-arn "$ALB_TARGET_GROUP_ARN" \
        --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`].Target.Id' \
        --output text)

    if [[ -z "$targets" ]]; then
        log "  WARNING: No healthy instances found in target group"
        CURRENT_INSTANCE_ID=""
    else
        CURRENT_INSTANCE_ID=$(echo "$targets" | head -1)
        log "  Current healthy instance: $CURRENT_INSTANCE_ID"
    fi
}

# ─── Step 3: Launch new instance from latest AMI ────────────────────────────

launch_new_instance() {
    if [[ "$SKIP_LAUNCH" == "true" ]]; then
        if [[ -z "$TARGET_INSTANCE_ID" ]]; then
            die "--skip-launch requires --instance-id"
        fi
        NEW_INSTANCE_ID="$TARGET_INSTANCE_ID"
        log "Step 3: Skipping launch, using existing instance: $NEW_INSTANCE_ID"
        return
    fi

    log "Step 3: Launching new instance from latest AMI..."

    # Find latest AMI (exclude sapporo images)
    local ami_info
    ami_info=$(aws ec2 describe-images \
        --owners "$CHIP_ATLAS_AWS_ACCOUNT_ID" \
        --query 'Images[*].[ImageId,CreationDate,Name]' \
        --output text | grep -v 'sapporo' | sort -k2 -r | head -1)

    if [[ -z "$ami_info" ]]; then
        die "No AMI found for account $CHIP_ATLAS_AWS_ACCOUNT_ID"
    fi

    local ami_id ami_date ami_name
    ami_id=$(echo "$ami_info" | awk '{print $1}')
    ami_date=$(echo "$ami_info" | awk '{print $2}')
    ami_name=$(echo "$ami_info" | awk '{print $3}')
    log "  Latest AMI: $ami_id (created: $ami_date, name: $ami_name)"

    # Warn if AMI is older than 2 days
    local ami_epoch now_epoch age_days
    ami_epoch=$(date -d "$ami_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${ami_date%%.*}" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    if [[ "$ami_epoch" -gt 0 ]]; then
        age_days=$(( (now_epoch - ami_epoch) / 86400 ))
        if [[ "$age_days" -gt 2 ]]; then
            log "  WARNING: AMI is ${age_days} days old. Consider creating a fresh AMI."
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [DRY RUN] Would launch instance from AMI $ami_id"
        NEW_INSTANCE_ID="i-dry-run-placeholder"
        return
    fi

    local instance_name="chip-atlas-deploy-${TIMESTAMP}"
    aws ec2 run-instances --count 1 \
        --launch-template "LaunchTemplateId=$AWS_EC2_LAUNCH_TEMPLATE_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${instance_name}}]" \
        --image-id "$ami_id" \
        > "$INSTANCE_INFO_FILE"

    NEW_INSTANCE_ID=$(jq -r '.Instances[0].InstanceId' "$INSTANCE_INFO_FILE")
    log "  Launched instance: $NEW_INSTANCE_ID (name: $instance_name)"
    log "  Instance info saved to: $INSTANCE_INFO_FILE"
}

# ─── Step 4: Wait for SSH ────────────────────────────────────────────────────

get_instance_ip() {
    aws ec2 describe-instances \
        --instance-ids "$1" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text
}

wait_for_ssh() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Step 4: [DRY RUN] Would wait for SSH on $NEW_INSTANCE_ID"
        return
    fi

    log "Step 4: Waiting for SSH access on $NEW_INSTANCE_ID..."

    local elapsed=0
    local interval=10
    while [[ $elapsed -lt $SSH_WAIT_MAX ]]; do
        NEW_INSTANCE_IP=$(get_instance_ip "$NEW_INSTANCE_ID")
        if [[ -n "$NEW_INSTANCE_IP" && "$NEW_INSTANCE_IP" != "None" ]]; then
            if ssh $SSH_OPTS "$SSH_USER@$NEW_INSTANCE_IP" "echo ok" &>/dev/null; then
                log "  SSH available at $NEW_INSTANCE_IP"
                return
            fi
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        log "  Waiting for SSH... (${elapsed}s / ${SSH_WAIT_MAX}s)"
    done

    die "SSH not available after ${SSH_WAIT_MAX}s"
}

# ─── Step 5: Provision instance ─────────────────────────────────────────────

provision_instance() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Step 5: [DRY RUN] Would provision instance $NEW_INSTANCE_ID"
        return
    fi

    log "Step 5: Provisioning instance $NEW_INSTANCE_IP..."

    ssh $SSH_OPTS "$SSH_USER@$NEW_INSTANCE_IP" bash -s <<'PROVISION_SCRIPT'
set -euo pipefail

echo "==> Pulling latest code..."
cd /home/ubuntu/chip-atlas
git fetch origin
git reset --hard origin/master

echo "==> Installing dependencies..."
bundle install --deployment --without development test

echo "==> Running security updates..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

echo "==> Deploying nginx config..."
sudo cp config/nginx/chip-atlas.conf /etc/nginx/sites-available/chip-atlas
sudo ln -sf /etc/nginx/sites-available/chip-atlas /etc/nginx/sites-enabled/chip-atlas
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

echo "==> Running database migrations..."
bundle exec rake db:migrate

echo "==> Loading metadata..."
bundle exec rake pj:load_metadata

echo "==> Restarting application..."
if [ -f tmp/pids/unicorn.pid ] && kill -0 $(cat tmp/pids/unicorn.pid) 2>/dev/null; then
    kill -USR2 $(cat tmp/pids/unicorn.pid)
    sleep 5
else
    bundle exec unicorn -c unicorn.rb -D
fi

echo "==> Provision complete"
PROVISION_SCRIPT

    log "  Provisioning complete"
}

# ─── Step 6: Wait for healthy ────────────────────────────────────────────────

wait_for_healthy() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Step 6: [DRY RUN] Would wait for /health to return 200"
        return
    fi

    log "Step 6: Waiting for /health to return 200 on $NEW_INSTANCE_IP..."

    local elapsed=0
    local interval=10
    while [[ $elapsed -lt $HEALTH_WAIT_MAX ]]; do
        local status_code
        status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
            "http://$NEW_INSTANCE_IP/health" 2>/dev/null || echo "000")

        if [[ "$status_code" == "200" ]]; then
            log "  Health check passed"
            curl -s "http://$NEW_INSTANCE_IP/health" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            return
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
        log "  Health check returned $status_code (${elapsed}s / ${HEALTH_WAIT_MAX}s)"
    done

    die "Health check did not pass after ${HEALTH_WAIT_MAX}s"
}

# ─── Step 7: Register in ALB ────────────────────────────────────────────────

register_in_alb() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Step 7: [DRY RUN] Would register $NEW_INSTANCE_ID in ALB target group"
        return
    fi

    log "Step 7: Registering $NEW_INSTANCE_ID in ALB target group..."

    aws elbv2 register-targets \
        --target-group-arn "$ALB_TARGET_GROUP_ARN" \
        --targets "Id=$NEW_INSTANCE_ID"

    # Wait for the new instance to become healthy in ALB
    log "  Waiting for instance to become healthy in ALB..."
    local elapsed=0
    local interval=15
    while [[ $elapsed -lt $HEALTH_WAIT_MAX ]]; do
        local state
        state=$(aws elbv2 describe-target-health \
            --target-group-arn "$ALB_TARGET_GROUP_ARN" \
            --targets "Id=$NEW_INSTANCE_ID" \
            --query 'TargetHealthDescriptions[0].TargetHealth.State' \
            --output text)

        if [[ "$state" == "healthy" ]]; then
            log "  Instance is healthy in ALB"
            return
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
        log "  ALB health state: $state (${elapsed}s / ${HEALTH_WAIT_MAX}s)"
    done

    die "Instance did not become healthy in ALB after ${HEALTH_WAIT_MAX}s"
}

# ─── Step 8: Deregister old instance ────────────────────────────────────────

deregister_old() {
    if [[ -z "${CURRENT_INSTANCE_ID:-}" ]]; then
        log "Step 8: No previous instance to deregister"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "Step 8: [DRY RUN] Would deregister $CURRENT_INSTANCE_ID from ALB"
        return
    fi

    log "Step 8: Deregistering old instance $CURRENT_INSTANCE_ID from ALB..."

    aws elbv2 deregister-targets \
        --target-group-arn "$ALB_TARGET_GROUP_ARN" \
        --targets "Id=$CURRENT_INSTANCE_ID"

    log "  Waiting ${DRAIN_WAIT}s for connection draining..."
    sleep "$DRAIN_WAIT"

    log "  Old instance $CURRENT_INSTANCE_ID has been deregistered from ALB"
    log ""
    log "  *** Old instance is NOT terminated. To terminate manually: ***"
    log "  aws ec2 terminate-instances --instance-ids $CURRENT_INSTANCE_ID"
    log ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    log "========================================="
    log "ChIP-Atlas Deployment"
    log "Timestamp: $TIMESTAMP"
    log "Dry run: $DRY_RUN"
    log "Skip launch: $SKIP_LAUNCH"
    log "Log file: $LOG_FILE"
    log "========================================="

    validate_aws
    get_current_instance
    launch_new_instance
    wait_for_ssh
    provision_instance
    wait_for_healthy
    register_in_alb
    deregister_old

    log "========================================="
    log "Deployment complete!"
    log "New instance: $NEW_INSTANCE_ID"
    if [[ -n "${CURRENT_INSTANCE_ID:-}" ]]; then
        log "Old instance (deregistered, NOT terminated): $CURRENT_INSTANCE_ID"
    fi
    log "========================================="
}

main
