#!/usr/bin/env bash
set -euo pipefail

# Creates Slack and PagerDuty notification channels from GSM secrets and links
# them to configured alert policies. Idempotent: will skip creation if channel
# with same display name exists. Secrets must be populated in GSM with the
# integration values.

PROJECT_ID="nexusshield-prod"
EMAIL_CHANNEL_NAME="Platform Security - Email"
SLACK_SECRET="slack-integration-webhook"
PAGERDUTY_SECRET="pagerduty-integration-key"
SLACK_DISPLAY="Cloud Monitoring - Slack (auto)"
PAGER_DISPLAY="PagerDuty - On-Call (auto)"

get_secret() {
  local name="$1"
  gcloud secrets versions access latest --secret="$name" --project="$PROJECT_ID" 2>/dev/null || echo ""
}

create_channel_if_missing() {
  local type=$1 display=$2 labels_json=$3
  # check existing channels
  existing=$(gcloud alpha monitoring channels list --project="$PROJECT_ID" --filter="displayName=$display" --format='value(name)' || true)
  if [ -n "$existing" ]; then
    echo "Channel already exists: $existing"
    echo "$existing"
    return 0
  fi
  payload=$(jq -n --arg type "$type" --arg dn "$display" --argjson labels "$labels_json" '{type:$type, displayName:$dn, labels:$labels, enabled:true}')
  TOKEN=$(gcloud auth print-access-token)
  curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/notificationChannels" -d "$payload" | jq -r '.name // empty'
}

echo "Preparing to create channels from GSM (if populated)"

# Slack
SLACK_WEBHOOK=$(get_secret "$SLACK_SECRET")
if [ -n "$SLACK_WEBHOOK" ] && [ "$SLACK_WEBHOOK" != "REPLACE_WITH_SLACK_WEBHOOK" ]; then
  echo "Creating Slack channel"
  labels=$(jq -n --arg webhook "$SLACK_WEBHOOK" '{webhook_url:$webhook, channel_name:"#alerts"}')
  create_channel_if_missing "slack_channel" "$SLACK_DISPLAY" "$labels" || true
else
  echo "Slack secret not populated; skip creating Slack channel. Put the webhook in GSM secret: $SLACK_SECRET"
fi

# PagerDuty
PD_KEY=$(get_secret "$PAGERDUTY_SECRET")
if [ -n "$PD_KEY" ] && [ "$PD_KEY" != "REPLACE_WITH_PAGERDUTY_KEY" ]; then
  echo "Creating PagerDuty channel"
  labels=$(jq -n --arg key "$PD_KEY" '{integration_key:$key}')
  create_channel_if_missing "pagerduty" "$PAGER_DISPLAY" "$labels" || true
else
  echo "PagerDuty secret not populated; skip creating PagerDuty channel. Put the integration key in GSM secret: $PAGERDUTY_SECRET"
fi

echo "Done. To link channels to policies, run the monitoring guide or provide channel names to this script."
