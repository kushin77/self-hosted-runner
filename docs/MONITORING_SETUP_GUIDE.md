# Cloud Monitoring Notification Setup Guide

## Overview
This guide completes the notification channel configuration for alert policies:
- `prevent-releases 5xx Count Alert`
- `Secret Access Denied Alert`

## Alert Policies Status ✅
Both alert policies have been created in Cloud Monitoring:
- **5xx Count Alert:** `projects/nexusshield-prod/alertPolicies/13444192473284444351`
- **Secret Access Denied Alert:** (pending ID confirmation)

## Notification Channels - Setup Instructions

### 1. Email Channel (Recommended for initial setup)

#### Quick Setup via API
```bash
PROJECT_ID="nexusshield-prod"
EMAIL="platform-security@nexusshield.io"

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/notificationChannels" \
  -d "{
    \"type\": \"email\",
    \"displayName\": \"Platform Security - Email\",
    \"labels\": {\"email_address\": \"$EMAIL\"},
    \"enabled\": true
  }"
```

#### Cloud Console UI
1. Navigate to Cloud Console → Monitoring → Notification channels
2. Click **Create Channel**
3. Select **Email** type
4. Enter email address: `platform-security@nexusshield.io`
5. Click **Create channel**
6. **Verify email** - check inbox for verification link

### 2. Slack Channel (Optional - for team notifications)

#### Prerequisites
- Create Slack App with incoming webhooks enabled
- Generate Webhook URL from Slack App settings

#### Setup via API
```bash
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/notificationChannels" \
  -d "{
    \"type\": \"slack_channel\",
    \"displayName\": \"Cloud Monitoring - Slack\",
    \"labels\": {\"channel_name\": \"#alerts\"},
    \"enabled\": true
  }"
```

### 3. PagerDuty Channel (Optional - for on-call routing)

#### Prerequisites
- PagerDuty account and service
- Integration key from PagerDuty service settings

#### Setup via API
```bash
PAGERDUTY_KEY="YOUR_INTEGRATION_KEY"

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/notificationChannels" \
  -d "{
    \"type\": \"pagerduty\",
    \"displayName\": \"PagerDuty - On-Call\",
    \"labels\": {\"integration_key\": \"$PAGERDUTY_KEY\"},
    \"enabled\": true
  }"
```

## Link Channels to Alert Policies

### Get Channel IDs
```bash
# List all notification channels
gcloud alpha monitoring channels list --project=nexusshield-prod --format='table(name,displayName,type)'
```

### Update Alert Policies
```bash
POLICY_ID="13444192473284444351"  # 5xx alert
CHANNEL_ID="projects/nexusshield-prod/notificationChannels/XXXXXXXXX"

gcloud alpha monitoring policies update $POLICY_ID \
  --notification-channels=$CHANNEL_ID \
  --project=nexusshield-prod
```

## Testing Alert Channels

### Send Test Notification
```bash
# Create test alert to trigger channels
gcloud alpha monitoring policies create \
  --notification-channels=$CHANNEL_ID \
  --display-name="Test Alert" \
  --condition-display-name="Test Condition" \
  --condition-threshold-value=0 \
  --condition-threshold-duration=60s \
  --condition-threshold-comparison=COMPARISON_GT \
  --project=nexusshield-prod
```

## Monitoring & Verification

After setup, verify:
- [ ] Email verification link received and clicked
- [ ] Slack/PagerDuty webhooks tested (if applicable)
- [ ] Alert policies linked to channels
- [ ] Test notification received

## Current Status

| Channel | Status | Action |
|---------|--------|--------|
| Email | ⏳ Creating | Awaiting verification |
| Slack | ❌ Not configured | Optional - requires setup |
| PagerDuty | ❌ Not configured | Optional - requires setup |

## Next Steps

1. **Immediate:** Create email notification channel
2. **24-hour:** Verify email and test alert delivery
3. **Optional:** Add Slack or PagerDuty for advanced routing
4. **Planning:** Setup on-call schedule if using PagerDuty

## References

- [Cloud Monitoring API Docs](https://cloud.google.com/monitoring/api/ref_v3/rest)
- [Notification Channel Types](https://cloud.google.com/monitoring/support/notification-channel-types)
- [Alert Policy Management](https://cloud.google.com/monitoring/alerts/best-practices)

---
Last Updated: 2026-03-11
Owner: Platform Security
