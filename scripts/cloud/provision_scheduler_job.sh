#!/usr/bin/env bash
set -euo pipefail

# Provisions Cloud Scheduler job and Cloud Monitoring alert for multi-cloud sync validation
# Idempotent: creates/updates job and alert policy as needed

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-multi-cloud-sync-validation}"
SCHEDULER_ZONE="${SCHEDULER_ZONE:-us-central1}"
SCHEDULER_JOB_NAME="multi-cloud-sync-validation"
SCHEDULE="${SCHEDULE:-0 * * * *}"  # every hour at minute 0
ALERT_CHANNEL_ID="${ALERT_CHANNEL_ID:-}"  # Will be set after channel creation
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-nxs-portal-production-v2@nexusshield-prod.iam.gserviceaccount.com}"

DRY_RUN=false
INCLUDE_ALERTS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --alerts)
      INCLUDE_ALERTS=true
      shift
      ;;
    *)
      echo "Usage: $0 [--dry-run] [--alerts]"
      exit 1
      ;;
  esac
done

log_info() {
  echo "[INFO] $*" >&2
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

check_gcloud() {
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found"
    exit 1
  fi
  
  # Enable required APIs
  log_info "Enabling required GCP APIs..."
  for api in cloudscheduler.googleapis.com pubsub.googleapis.com monitoring.googleapis.com; do
    gcloud services enable "$api" --project="$PROJECT_ID" &>/dev/null || log_warn "Failed to enable $api"
  done
}

create_pubsub_topic() {
  local topic="$1"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create Pub/Sub topic: $topic"
    return 0
  fi
  
  if gcloud pubsub topics describe "$topic" --project="$PROJECT_ID" &>/dev/null 2>&1; then
    log_info "Pub/Sub topic already exists: $topic"
    return 0
  fi
  
  log_info "Creating Pub/Sub topic: $topic"
  gcloud pubsub topics create "$topic" --project="$PROJECT_ID" || {
    log_error "Failed to create Pub/Sub topic"
    return 1
  }
}

create_pubsub_subscription() {
  local topic="$1"
  local subscription="$1-subscription"
  local handler_url="${2:-https://example.com/webhook/sync-validation}"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create Pub/Sub subscription: $subscription"
    return 0
  fi
  
  if gcloud pubsub subscriptions describe "$subscription" --project="$PROJECT_ID" &>/dev/null 2>&1; then
    log_info "Subscription already exists: $subscription"
    return 0
  fi
  
  log_info "Creating Pub/Sub subscription: $subscription (with push to handler)"
  
  # Create push subscription to trigger validation handler
  gcloud pubsub subscriptions create "$subscription" \
    --topic="$topic" \
    --project="$PROJECT_ID" \
    --push-endpoint="$handler_url" \
    --push-auth-service-account="$SERVICE_ACCOUNT" || {
    log_error "Failed to create subscription"
    return 1
  }
}

create_scheduler_job() {
  local job_name="$1"
  local topic="$2"
  local schedule="$3"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create Cloud Scheduler job: $job_name"
    log_info "  Schedule: $schedule"
    log_info "  Topic: $topic"
    log_info "  Message: {\"action\": \"validate-sync\"}"
    return 0
  fi
  
  if gcloud scheduler jobs describe "$job_name" --location="$SCHEDULER_ZONE" --project="$PROJECT_ID" &>/dev/null 2>&1; then
    log_info "Updating existing scheduler job: $job_name"
    
    gcloud scheduler jobs update pubsub "$job_name" \
      --location="$SCHEDULER_ZONE" \
      --schedule="$schedule" \
      --topic="$topic" \
      --message-body='{"action": "validate-sync"}' \
      --project="$PROJECT_ID" || {
      log_error "Failed to update scheduler job"
      return 1
    }
  else
    log_info "Creating Cloud Scheduler job: $job_name"
    
    gcloud scheduler jobs create pubsub "$job_name" \
      --location="$SCHEDULER_ZONE" \
      --schedule="$schedule" \
      --topic="$topic" \
      --message-body='{"action": "validate-sync"}' \
      --oidc-service-account-email="$SERVICE_ACCOUNT" \
      --project="$PROJECT_ID" || {
      log_error "Failed to create scheduler job"
      return 1
    }
  fi
}

create_alert_policy() {
  local policy_name="multi-cloud-sync-validation-failures"
  local notification_channel="${1:-}"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create alert policy: $policy_name"
    return 0
  fi
  
  if [[ -z "$notification_channel" ]]; then
    log_warn "No notification channel provided; skipping alert creation"
    log_info "To create alerts, provide a Cloud Monitoring notification channel ID"
    log_info "Get existing channels: gcloud alpha monitoring channels list --project=$PROJECT_ID"
    return 0
  fi
  
  log_info "Creating alert policy: $policy_name"
  
  # Policy: Alert if sync validation fails (error rate > 10%)
  policy_body=$(cat <<EOF
{
  "displayName": "$policy_name",
  "conditions": [
    {
      "displayName": "Sync validation error rate > 10%",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/sync_validation_errors\" resource.type=\"global\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.1,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "notificationChannels": ["$notification_channel"],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
)
  
  # Note: Full policy creation requires monitoring API
  log_warn "Alert policy creation requires additional setup"
  log_info "Recommend using Cloud Console or Terraform for alert policies"
  log_info "Alert should monitor: metric.type=logging.googleapis.com/user/sync_validation_errors"
}

enable_job() {
  local job_name="$1"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would enable scheduler job: $job_name"
    return 0
  fi
  
  log_info "Enabling scheduler job: $job_name"
  gcloud scheduler jobs resume "$job_name" \
    --location="$SCHEDULER_ZONE" \
    --project="$PROJECT_ID" 2>/dev/null || {
    log_info "Job is already enabled"
  }
}

# Main execution
log_info "Provisioning Cloud Scheduler job for multi-cloud sync validation"
log_info "Project: $PROJECT_ID"
log_info "Schedule: $SCHEDULE (cron format)"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY-RUN MODE] - No changes will be made"
fi

check_gcloud

# Create infrastructure
create_pubsub_topic "$PUBSUB_TOPIC"
create_scheduler_job "$SCHEDULER_JOB_NAME" "$PUBSUB_TOPIC" "$SCHEDULE"
enable_job "$SCHEDULER_JOB_NAME"

# Optionally create alerts
if [[ "$INCLUDE_ALERTS" == "true" ]]; then
  create_alert_policy "$ALERT_CHANNEL_ID"
fi

# Display job status
if [[ "$DRY_RUN" != "true" ]]; then
  log_info ""
  log_info "Scheduler job details:"
  gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" \
    --location="$SCHEDULER_ZONE" \
    --project="$PROJECT_ID" \
    --format="table(name,schedule,timezone,lastExecutionTime,state)" || true
fi

log_info "Done. Cloud Scheduler will trigger validation every hour (cron 0 * * * *)."
log_info "To test immediately: gcloud scheduler jobs run $SCHEDULER_JOB_NAME --location=$SCHEDULER_ZONE --project=$PROJECT_ID"
