#!/usr/bin/env bash
set -euo pipefail

# Create synthetic health-check alert policy (idempotent)
# Usage: ./create_alert_policy.sh [PROJECT_ID]

PROJECT_ID=${1:-nexusshield-prod}
ALERT_NAME="synthetic-uptime-check-failure-alert"
EMAIL_CHANNEL="projects/${PROJECT_ID}/notificationChannels/16284129900945210911"
CRITICAL_CHANNEL="projects/${PROJECT_ID}/notificationChannels/8473220498823178928"

echo "Creating alert policy in project: $PROJECT_ID"
echo "Email channel: $EMAIL_CHANNEL"
echo "Critical channel: $CRITICAL_CHANNEL"

# Check if alert policy already exists
EXISTING=$(gcloud monitoring policies list \
  --project="$PROJECT_ID" \
  --filter="displayName:${ALERT_NAME}" \
  --format="value(name)" 2>/dev/null | head -1 || true)

if [[ -n "$EXISTING" ]]; then
  echo "Alert policy already exists: $EXISTING"
  echo "(Idempotent: no changes needed)"
  exit 0
fi

# Create the alert policy using gcloud
gcloud monitoring policies create \
  --notification-channels="$EMAIL_CHANNEL" \
  --notification-channels="$CRITICAL_CHANNEL" \
  --display-name="$ALERT_NAME" \
  --project="$PROJECT_ID" \
  --condition-display-name="Synthetic log metric missing (< 1 in 5min)" \
  --condition-threshold-value=0 \
  --condition-threshold-filter='metric.type = "logging.googleapis.com/user/synthetic_uptime_log_count"' \
  --condition-threshold-comparison=COMPARISON_LT \
  --condition-duration=300s 2>&1 | tee -a alert_policy_create.log

echo "Alert policy created successfully"
