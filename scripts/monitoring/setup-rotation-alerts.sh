#!/bin/bash
# Cloud Monitoring Alert Setup for Credential Rotation
# This script creates a monitoring alert for failed rotation builds
# Usage: bash setup-rotation-alerts.sh

PROJECT="nexusshield-prod"
LOCATION="us-central1"
ALERT_CHANNEL_NAME="Credential Rotation Failures"
POLICY_NAME="credential-rotation-failure-alert"

set -e

echo "Setting up Cloud Monitoring alerts for credential rotation..."
echo ""

# Create notification channel (email)
echo "1. Creating notification channel (email)..."
CHANNEL=$(gcloud alpha monitoring channels create \
  --display-name="$ALERT_CHANNEL_NAME" \
  --type=email \
  --channel-labels=email_address=security-team@example.com \
  --project="$PROJECT" 2>/dev/null || echo "Channel may already exist")

if [[ -n "$CHANNEL" ]]; then
  CHANNEL_ID=$(echo "$CHANNEL" | grep -o "projects/.*" | cut -d'/' -f4)
  echo "✅ Notification channel created: $CHANNEL_ID"
else
  # Get existing channel
  CHANNEL_ID=$(gcloud alpha monitoring channels list \
    --project="$PROJECT" \
    --filter="displayName:$ALERT_CHANNEL_NAME" \
    --format='value(name)' 2>/dev/null | cut -d'/' -f4 | head -1)
  echo "ℹ️  Using existing notification channel: $CHANNEL_ID"
fi

echo ""
echo "2. Creating alert policy for build failures..."

# Create alert policy JSON
cat > /tmp/rotation-alert-policy.json <<EOF
{
  "displayName": "$POLICY_NAME",
  "conditions": [
    {
      "displayName": "Cloud Build Rotation Job Failure",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_build\" AND resource.labels.build_id=~\".*credential-rotation.*\" AND metric.type=\"cloudbuild.googleapis.com/build/status\" AND metric.value_type=\"INT64\" AND metric.labels.build_status=\"FAILURE\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s"
      }
    }
  ],
  "notificationChannels": ["projects/$PROJECT/notificationChannels/$CHANNEL_ID"],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

echo "✅ Alert policy configured for email notifications"
echo ""
echo "3. Next Steps:"
echo "   - Replace email_address in notification channel with your actual email"
echo "   - Deploy alert policy via Cloud Console or:"
echo "     gcloud alpha monitoring policies create --policy-from-file=/tmp/rotation-alert-policy.json --project=$PROJECT"
echo ""
echo "4. Manual Monitoring Commands:"
echo "   # Check recent builds"
echo "   gcloud builds list --project=$PROJECT --limit=5"
echo ""
echo "   # View build logs"
echo "   gcloud builds log <BUILD_ID> --project=$PROJECT"
echo ""
echo "   # Check build failure status"
echo "   gcloud builds list --project=$PROJECT --filter='status=FAILURE' --limit=10"
echo ""
