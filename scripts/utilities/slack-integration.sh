#!/bin/bash
################################################################################
# SLACK INTEGRATION MODULE
# Tier 1 Enhancement: Real-time incident notifications and status updates
# Status: PRODUCTION READY
################################################################################

set -euo pipefail

SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
SLACK_CHANNEL="${SLACK_CHANNEL:-#incidents}"
LOG_DIR="${LOG_DIR:-/var/log/slack-integration}"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/slack-$(date +%Y%m%d).log"

# === VALIDATION ===
validate_webhook() {
  if [[ -z "$SLACK_WEBHOOK" ]]; then
    echo "[ERROR] SLACK_WEBHOOK not configured in environment" >&2
    return 1
  fi
}

# === NOTIFICATION FUNCTIONS ===
notify_incident() {
  local severity="$1"
  local title="$2"
  local description="$3"
  local metadata="${4:-}"
  
  validate_webhook || return 1
  
  local color
  case "$severity" in
    critical) color="danger" ;;
    warning) color="warning" ;;
    info) color="good" ;;
    *) color="#439FE0" ;;
  esac
  
  local payload=$(cat <<EOF
{
  "channel": "$SLACK_CHANNEL",
  "attachments": [
    {
      "fallback": "$title",
      "color": "$color",
      "title": "🚨 $title",
      "text": "$description",
      "fields": [
        {
          "title": "Severity",
          "value": "$(echo $severity | tr 'a-z' 'A-Z')",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "short": true
        },
        {
          "title": "Metadata",
          "value": "$metadata",
          "short": false
        }
      ],
      "footer": "Incident Monitoring",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
  
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$payload" > /dev/null && echo "[$(date +'%Y-%m-%d %H:%M:%S')] Notification sent: $title" | tee -a "$LOG_FILE"
}

notify_recovery() {
  local service="$1"
  local recovery_time="$2"
  
  validate_webhook || return 1
  
  local payload=$(cat <<EOF
{
  "channel": "$SLACK_CHANNEL",
  "attachments": [
    {
      "fallback": "Recovery: $service",
      "color": "good",
      "title": "✅ Service Recovered",
      "text": "$service has been recovered",
      "fields": [
        {
          "title": "Service",
          "value": "$service",
          "short": true
        },
        {
          "title": "Recovery Time",
          "value": "${recovery_time}s",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "short": false
        }
      ],
      "footer": "Incident Monitoring",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
  
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$payload" > /dev/null && echo "[$(date +'%Y-%m-%d %H:%M:%S')] Recovery notification sent" | tee -a "$LOG_FILE"
}

notify_scheduled_maintenance() {
  local maintenance_type="$1"
  local start_time="$2"
  local duration="$3"
  
  validate_webhook || return 1
  
  local payload=$(cat <<EOF
{
  "channel": "$SLACK_CHANNEL",
  "attachments": [
    {
      "fallback": "Scheduled maintenance: $maintenance_type",
      "color": "#439FE0",
      "title": "🔧 Scheduled Maintenance",
      "text": "Maintenance window starting: $start_time",
      "fields": [
        {
          "title": "Maintenance Type",
          "value": "$maintenance_type",
          "short": true
        },
        {
          "title": "Duration",
          "value": "${duration} minutes",
          "short": true
        },
        {
          "title": "Start Time",
          "value": "$start_time",
          "short": false
        }
      ],
      "footer": "Infrastructure Management",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
  
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$payload" > /dev/null
}

notify_cost_alert() {
  local alert_type="$1"
  local current_cost="$2"
  local threshold="$3"
  
  validate_webhook || return 1
  
  local payload=$(cat <<EOF
{
  "channel": "$SLACK_CHANNEL",
  "attachments": [
    {
      "fallback": "Cost alert: $alert_type",
      "color": "warning",
      "title": "💰 Cost Alert",
      "text": "$alert_type - Review optimization opportunities",
      "fields": [
        {
          "title": "Alert Type",
          "value": "$alert_type",
          "short": true
        },
        {
          "title": "Current Cost",
          "value": "\$$current_cost",
          "short": true
        },
        {
          "title": "Threshold",
          "value": "\$$threshold",
          "short": true
        },
        {
          "title": "Status",
          "value": "Action required",
          "short": true
        }
      ],
      "footer": "Cost Monitoring",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
  
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$payload" > /dev/null
}

notify_deployment() {
  local deployment_name="$1"
  local status="$2"
  local version="$3"
  
  validate_webhook || return 1
  
  local color="good"
  [[ "$status" != "success" ]] && color="warning"
  
  local payload=$(cat <<EOF
{
  "channel": "$SLACK_CHANNEL",
  "attachments": [
    {
      "fallback": "Deployment: $deployment_name",
      "color": "$color",
      "title": "📦 Deployment Event",
      "text": "Deployment $deployment_name: $status",
      "fields": [
        {
          "title": "Deployment",
          "value": "$deployment_name",
          "short": true
        },
        {
          "title": "Status",
          "value": "$(echo $status | tr 'a-z' 'A-Z')",
          "short": true
        },
        {
          "title": "Version",
          "value": "$version",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "short": true
        }
      ],
      "footer": "Deployment Monitoring",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
  
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$payload" > /dev/null
}

send_daily_digest() {
  validate_webhook || return 1
  
  # Collect metrics from the day
  local incidents_count="${1:-0}"
  local recovery_avg="${2:-0}"
  local uptime="${3:-99.9}"
  
  local payload=$(cat <<EOF
{
  "channel": "$SLACK_CHANNEL",
  "attachments": [
    {
      "fallback": "Daily Digest",
      "color": "good",
      "title": "📊 Daily Operations Digest",
      "text": "Summary of infrastructure operations",
      "fields": [
        {
          "title": "Critical Incidents",
          "value": "$incidents_count",
          "short": true
        },
        {
          "title": "Avg Recovery Time",
          "value": "${recovery_avg}s",
          "short": true
        },
        {
          "title": "Uptime",
          "value": "$uptime%",
          "short": true
        },
        {
          "title": "Date",
          "value": "$(date +%Y-%m-%d)",
          "short": true
        }
      ],
      "footer": "Daily Digest",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
  
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$payload" > /dev/null
}

# === MAIN ===
case "${1:-}" in
  incident)
    notify_incident "$2" "$3" "$4" "${5:-}"
    ;;
  recovery)
    notify_recovery "$2" "$3"
    ;;
  maintenance)
    notify_scheduled_maintenance "$2" "$3" "$4"
    ;;
  cost-alert)
    notify_cost_alert "$2" "$3" "$4"
    ;;
  deployment)
    notify_deployment "$2" "$3" "$4"
    ;;
  digest)
    send_daily_digest "${2:-0}" "${3:-0}" "${4:-99.9}"
    ;;
  *)
    echo "Usage: $0 {incident|recovery|maintenance|cost-alert|deployment|digest} ..."
    ;;
esac
