#!/bin/bash
#
# Hardened Deployment Configuration
# Sourced by post-push-deploy.sh
#

# Target infrastructure
export TARGET_HOST="192.168.168.42"
export SERVICE_ACCOUNT="akushnir"
export SSH_KEY="$HOME/.ssh/id_ed25519"

# Deployment options
export DRY_RUN="false"
export SKIP_DEPLOYMENT="false"
export AUTO_ROLLBACK="true"
export HEALTH_CHECK_TIMEOUT="300"  # 5 minutes

# Hardened deployment flags
export USE_HARDENED_CONFIG="true"
export REQUIRE_SECRETS="true"
export FAIL_ON_MISSING_SECRETS="true"

# Logging
export DEPLOYMENT_LOG_DIR="/tmp/deployments"
mkdir -p "$DEPLOYMENT_LOG_DIR"

# Audit trail
export AUDIT_TRAIL="/var/log/nexusshield-deployment.jsonl"

# Notifications
export NOTIFY_ON_SUCCESS="true"
export NOTIFY_ON_FAILURE="true"
export SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

# GSM Project for secrets
export GSM_PROJECT="nexusshield-prod"
