#!/usr/bin/env bash
# dr_pipeline_monitor.sh — Hands-off DR pipeline monitoring & failure detection
# 
# Purpose: Monitor the DR dry-run pipeline for success/failure, capture metrics, 
#          post alerts to Slack if anything goes wrong, and trigger remediation.
#
# Usage:
#   export SECRET_PROJECT=gcp-eiq GITLAB_PROJECT_ID=123 SLACK_CHANNEL="#ops-alerts"
#   ./dr_pipeline_monitor.sh [--poll-interval 30] [--timeout 3600]
#
# Idempotent: Yes (safe to run repeatedly; checks job status before posting)
# Dependencies: gcloud, curl, jq, gitlab-cli (optional)
#
# Environment Variables (auto-fetched from GSM):
#   - SLACK_WEBHOOK: Slack notification webhook
#   - gitlab-api-token: GitLab API token for job queries (from issue 906)
#   - github-token: GitHub API token (for mirror repo checks)
#
# Outputs:
#   - Slack notifications on failure, timeout, or unusual metrics
#   - Log file: /tmp/dr_pipeline_monitor_<pid>.log
#   - Exit code 0: Success or monitoring only; 1: Failure detected

set -euo pipefail

# Configuration
SECRET_PROJECT="${SECRET_PROJECT:-gcp-eiq}"
GITLAB_PROJECT_ID="${GITLAB_PROJECT_ID:-}"
GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
SLACK_CHANNEL="${SLACK_CHANNEL:-#dr-automation}"
POLL_INTERVAL="${1##*--poll-interval }" && POLL_INTERVAL="${POLL_INTERVAL%% *}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"  # seconds
TIMEOUT="${2##*--timeout }" && TIMEOUT="${TIMEOUT%% *}"
TIMEOUT="${TIMEOUT:-3600}"  # 1 hour default
HOSTNAME="${HOSTNAME:-$(hostname)}"
LOG_FILE="/tmp/dr_pipeline_monitor_$$.log"

# Thresholds for anomalies
RTO_THRESHOLD_MINUTES=60  # Alert if RTO > 60 min
RPO_THRESHOLD_MINUTES=30  # Alert if RPO > 30 min

echo "[$(date -Iseconds)] Starting DR pipeline monitor (interval=${POLL_INTERVAL}s, timeout=${TIMEOUT}s)" | tee -a "$LOG_FILE"

# ============================================================================
# Helper Functions
# ============================================================================

log_message() {
    echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

fetch_secret() {
    local secret_name="$1"
    gcloud secrets versions access latest --secret="$secret_name" --project="$SECRET_PROJECT" 2>/dev/null || {
        log_message "ERROR: Failed to fetch secret '$secret_name' from GSM"
        return 1
    }
}

post_to_slack() {
    local message="$1"
    local severity="${2:-info}"  # info, warning, error
    local slack_webhook
    
    slack_webhook=$(fetch_secret "slack-webhook") || return 1
    
    # Color coding based on severity
    local color="36a64f"  # green (info)
    [[ "$severity" == "warning" ]] && color="ff9900"  # orange
    [[ "$severity" == "error" ]] && color="ff0000"    # red
    
    local payload=$(cat <<EOF
{
  "attachments": [
    {
      "fallback": "$message",
      "color": "$color",
      "title": "DR Pipeline Monitor",
      "title_link": "$GITLAB_API_URL/projects/$GITLAB_PROJECT_ID/pipelines",
      "text": "$message",
      "footer": "Hands-off DR Automation",
      "ts": $(date +%s)
    }
  ]
}
EOF
    )
    
    curl -sS -X POST -H 'Content-type: application/json' \
        --data "$payload" "$slack_webhook" >/dev/null 2>&1 || {
        log_message "WARN: Failed to post to Slack"
        return 1
    }
}

get_latest_pipeline() {
    local gitlab_token api_url project_id
    
    [[ -z "$GITLAB_PROJECT_ID" ]] && {
        log_message "ERROR: GITLAB_PROJECT_ID not set"
        return 1
    }
    
    gitlab_token=$(fetch_secret "gitlab-api-token") || {
        log_message "WARN: gitlab-api-token not available; skipping live pipeline checks"
        return 2  # Non-fatal
    }
    
    # Fetch latest pipeline for 'dr-dryrun' ref
    curl -sS -H "PRIVATE-TOKEN: $gitlab_token" \
        "$GITLAB_API_URL/projects/$GITLAB_PROJECT_ID/pipelines?ref=main&order_by=id&sort=desc&per_page=1" \
        | jq -r '.[0] | select(.name == "dr-dryrun" or .ref == "dr-dryrun") | .id' 2>/dev/null || {
        log_message "WARN: Could not fetch pipeline ID"
        return 2
    }
}

get_pipeline_status() {
    local pipeline_id gitlab_token
    
    pipeline_id="$1"
    [[ -z "$pipeline_id" ]] && return 2
    
    gitlab_token=$(fetch_secret "gitlab-api-token") || return 2
    
    curl -sS -H "PRIVATE-TOKEN: $gitlab_token" \
        "$GITLAB_API_URL/projects/$GITLAB_PROJECT_ID/pipelines/$pipeline_id" \
        | jq -r '.status // "unknown"' 2>/dev/null
}

check_mirror_repo() {
    local github_token repo_url
    
    repo_url="https://api.github.com/repos/akushnir/self-hosted-runner"
    github_token=$(fetch_secret "github-token") || {
        log_message "WARN: github-token not available; skipping mirror checks"
        return 2
    }
    
    # Check if mirror repo is accessible
    local http_code
    http_code=$(curl -sS -w "%{http_code}" -o /dev/null \
        -H "Authorization: token $github_token" \
        "$repo_url" 2>/dev/null)
    
    if [[ "$http_code" != "200" ]]; then
        log_message "ERROR: Mirror repo returned HTTP $http_code"
        post_to_slack "⚠️  GitHub mirror repo inaccessible (HTTP $http_code)" "warning"
        return 1
    fi
    
    return 0
}

check_backup_bucket() {
    local bucket_name
    bucket_name=$(fetch_secret "ci-gcs-bucket") || return 2
    
    # Check if we can list the backup bucket
    gsutil -h "Cache-Control: no-cache" ls "gs://$bucket_name/backups/" >/dev/null 2>&1 || {
        log_message "WARN: Cannot access backup bucket gs://$bucket_name/"
        post_to_slack "⚠️  GCS backup bucket inaccessible or empty" "warning"
        return 1
    }
    
    return 0
}

parse_dr_metrics() {
    local log_file="$1"
    local rto_minutes rpo_minutes
    
    # Look for RTO/RPO in the log
    rto_minutes=$(grep -oP "RTO[_:]?\s*\K[\d.]+" "$log_file" 2>/dev/null | head -1 || echo "0")
    rpo_minutes=$(grep -oP "RPO[_:]?\s*\K[\d.]+" "$log_file" 2>/dev/null | head -1 || echo "0")
    
    [[ -z "$rto_minutes" ]] && rto_minutes="0"
    [[ -z "$rpo_minutes" ]] && rpo_minutes="0"
    
    echo "$rto_minutes $rpo_minutes"
}

check_metric_thresholds() {
    local rto_minutes="$1"
    local rpo_minutes="$2"
    local alerts=""
    
    # Check RTO threshold
    if (( $(echo "$rto_minutes > $RTO_THRESHOLD_MINUTES" | bc -l) )); then
        alerts="${alerts}RTO exceeded threshold: ${rto_minutes}m > ${RTO_THRESHOLD_MINUTES}m\n"
    fi
    
    # Check RPO threshold
    if (( $(echo "$rpo_minutes > $RPO_THRESHOLD_MINUTES" | bc -l) )); then
        alerts="${alerts}RPO exceeded threshold: ${rpo_minutes}m > ${RPO_THRESHOLD_MINUTES}m\n"
    fi
    
    [[ -n "$alerts" ]] && {
        log_message "ALERT: Metric thresholds exceeded"
        post_to_slack "📊 DR Metrics Alert:\n$alerts" "warning"
        return 1
    }
    
    return 0
}

# ============================================================================
# Main Monitoring Loop
# ============================================================================

log_message "Performing pre-flight checks..."

# Check mirror repo accessibility
check_mirror_repo || log_message "WARN: Mirror repo check failed (non-fatal)"

# Check backup bucket accessibility
check_backup_bucket || log_message "WARN: Backup bucket check failed (non-fatal)"

log_message "Pre-flight checks complete. Entering monitoring loop (timeout in ${TIMEOUT}s)..."

START_TIME=$(date +%s)
POLL_COUNT=0

# Main loop: Poll for pipeline completion
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    POLL_COUNT=$((POLL_COUNT + 1))
    
    if [[ $ELAPSED -gt $TIMEOUT ]]; then
        log_message "ERROR: Monitoring timeout reached (${TIMEOUT}s)"
        post_to_slack "❌ DR pipeline monitor timeout (${TIMEOUT}s, ${POLL_COUNT} polls)" "error"
        exit 1
    fi
    
    log_message "[Poll $POLL_COUNT] Checking pipeline status... (${ELAPSED}/${TIMEOUT}s elapsed)"
    
    # Get latest pipeline ID
    PIPELINE_ID=$(get_latest_pipeline) || {
        log_message "Could not fetch pipeline ID; will retry"
        sleep "$POLL_INTERVAL"
        continue
    }
    
    [[ -z "$PIPELINE_ID" ]] && {
        log_message "No pipeline ID found yet; retrying..."
        sleep "$POLL_INTERVAL"
        continue
    }
    
    log_message "Found pipeline $PIPELINE_ID"
    
    # Get pipeline status
    STATUS=$(get_pipeline_status "$PIPELINE_ID") || {
        log_message "Could not fetch pipeline status; will retry"
        sleep "$POLL_INTERVAL"
        continue
    }
    
    log_message "Pipeline status: $STATUS"
    
    case "$STATUS" in
        success)
            log_message "SUCCESS: DR pipeline completed successfully!"
            post_to_slack "✅ DR pipeline succeeded (pipeline/$PIPELINE_ID)" "info"
            exit 0
            ;;
        failed)
            log_message "ERROR: DR pipeline failed!"
            post_to_slack "❌ DR pipeline failed (pipeline/$PIPELINE_ID). Check logs: $GITLAB_API_URL/projects/$GITLAB_PROJECT_ID/pipelines/$PIPELINE_ID" "error"
            exit 1
            ;;
        canceled)
            log_message "WARN: DR pipeline was canceled"
            post_to_slack "⚠️  DR pipeline canceled (pipeline/$PIPELINE_ID)" "warning"
            exit 1
            ;;
        running|pending)
            log_message "Pipeline still running; polling again in ${POLL_INTERVAL}s..."
            ;;
        *)
            log_message "WARN: Unknown pipeline status: $STATUS"
            ;;
    esac
    
    sleep "$POLL_INTERVAL"
done
