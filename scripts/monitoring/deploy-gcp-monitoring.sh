#!/bin/bash
# Deploy Phase-4 Observability Framework
# GCP Cloud Monitoring + Dashboard + Alert Policies
# Author: GitHub Copilot (Autonomous Agent)
# Date: 2026-03-12

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
NOTIFICATION_CHANNELS_CSV="${MONITORING_NOTIFICATION_CHANNELS:-}"
AUDIT_DATASET="${MONITORING_AUDIT_DATASET:-audit_logs}"
BQ_LOCATION="${MONITORING_BQ_LOCATION:-US}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
AUDIT_LOG="logs/phase4-monitoring-deploy-${TIMESTAMP}.jsonl"

mkdir -p logs

# Log audit entry
log_event() {
  local event="$1"
  local status="$2"
  local details="${3:-}"
  
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\",\"status\":\"${status}\",\"details\":\"${details}\"}" >> "${AUDIT_LOG}"
}

log_event "phase4_monitoring_deploy_start" "started" "GCP monitoring infrastructure deployment"

for cmd in gcloud jq bq curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

build_notification_channels_json() {
  if [ -z "$NOTIFICATION_CHANNELS_CSV" ]; then
    echo "[]"
    return 0
  fi

  local channels_json="[]"
  IFS=',' read -r -a channels <<< "$NOTIFICATION_CHANNELS_CSV"
  for channel in "${channels[@]}"; do
    channel="$(echo "$channel" | xargs)"
    if [ -n "$channel" ]; then
      channels_json=$(echo "$channels_json" | jq --arg c "$channel" '. + [$c]')
    fi
  done
  echo "$channels_json"
}

create_metric_descriptor_if_missing() {
  local metric_type="$1"
  local display_name="$2"
  local description="$3"
  local value_type="$4"
  local metric_kind="$5"

  local token
  token="$(gcloud auth print-access-token)"

  local payload
  payload=$(jq -n \
    --arg t "custom.googleapis.com/${metric_type}" \
    --arg dn "$display_name" \
    --arg desc "$description" \
    --arg vt "$value_type" \
    --arg mk "$metric_kind" \
    '{type:$t, displayName:$dn, description:$desc, valueType:$vt, metricKind:$mk}')

  local response
  response=$(curl -sS -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/metricDescriptors" \
    -d "$payload")

  if echo "$response" | jq -e '.name? // empty' >/dev/null 2>&1; then
    echo "Created metric descriptor custom.googleapis.com/${metric_type}"
    return 0
  fi

  if echo "$response" | jq -e '.error.message? | test("Already exists"; "i")' >/dev/null 2>&1; then
    echo "Metric already exists (idempotent): custom.googleapis.com/${metric_type}"
    return 0
  fi

  echo "Failed to create metric descriptor custom.googleapis.com/${metric_type}: $response" >&2
  return 1
}

# ============================================================================
# 1. Create Log Router Sink for Credential Audit Trail
# ============================================================================
echo "📊 Creating log router sink..."

echo "Ensuring BigQuery dataset exists for monitoring audit logs..."
if ! bq --project_id="${PROJECT_ID}" show --format=none "${PROJECT_ID}:${AUDIT_DATASET}" >/dev/null 2>&1; then
  bq --project_id="${PROJECT_ID}" mk --dataset --location="${BQ_LOCATION}" "${PROJECT_ID}:${AUDIT_DATASET}" >/dev/null
fi

# Check if sink already exists (idempotent)
if ! gcloud logging sinks describe credential-audit-sink --project="${PROJECT_ID}" &>/dev/null; then
  gcloud logging sinks create credential-audit-sink \
    "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${AUDIT_DATASET}" \
    --log-filter='resource.type="cloud_function" OR resource.type="cloud_run_job"' \
    --project="${PROJECT_ID}"
  
  log_event "log_sink_created" "success" "credential-audit-sink configured"
else
  echo "Log sink already exists (idempotent)"
  log_event "log_sink_exists" "success" "credential-audit-sink already present"
fi

# ============================================================================
# 2. Create Custom Metrics for Credential Health
# ============================================================================
echo "📈 Creating custom metrics..."

# Metric 1: Credential Age (seconds)
create_metric_descriptor_if_missing \
  "credential_age_seconds" \
  "Credential Age" \
  "Age of current credential in seconds" \
  "INT64" \
  "GAUGE"

# Metric 2: Failover Latency (milliseconds)
create_metric_descriptor_if_missing \
  "failover_latency_ms" \
  "Failover Latency" \
  "Latency of credential failover chain" \
  "DOUBLE" \
  "GAUGE"

# Metric 3: Layer Availability (0=down, 1=up)
create_metric_descriptor_if_missing \
  "layer_status" \
  "Layer Status" \
  "Credential layer availability status" \
  "INT64" \
  "GAUGE"

log_event "custom_metrics_created" "success" "3 custom metrics registered"

# ============================================================================
# 3. Create Monitoring Dashboard
# ============================================================================
echo "📊 Creating monitoring dashboard..."

DASHBOARD_NAME="Phase-4: AWS OIDC Credential Failover Dashboard"

# Check if dashboard exists by display name
if ! gcloud monitoring dashboards list --project="${PROJECT_ID}" --filter="displayName='${DASHBOARD_NAME}'" --format='value(name)' | grep -q .; then
  cat > /tmp/dashboard.json << 'DASHBOARD_JSON'
{
  "displayName": "Phase-4: AWS OIDC Credential Failover Dashboard",
  "gridLayout": {
    "widgets": [
      {
        "title": "Failover Chain Status",
        "xyChart": {
          "chartOptions": {
            "mode": "COLOR"
          },
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"custom.googleapis.com/failover_latency_ms\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }
          ]
        }
      },
      {
        "title": "Credential Layer Availability",
        "xyChart": {
          "chartOptions": {
            "mode": "COLOR"
          },
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"custom.googleapis.com/layer_status\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }
          ]
        }
      },
      {
        "title": "Credential Age",
        "xyChart": {
          "chartOptions": {
            "mode": "COLOR"
          },
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"custom.googleapis.com/credential_age_seconds\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }
          ]
        }
      }
    ]
  }
}
DASHBOARD_JSON

  # Create dashboard
  gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json \
    --project="${PROJECT_ID}"
  
  log_event "dashboard_created" "success" "Phase-4 credential failover dashboard deployed"
else
  echo "Dashboard already exists (idempotent)"
  log_event "dashboard_exists" "success" "dashboard already present"
fi

# ============================================================================
# 4. Create Alert Policies
# ============================================================================
echo "🚨 Creating alert policies..."

ALERT_POLICY_COUNT=0

# Alert 1: High Failover Latency
if ! gcloud monitoring policies list --filter="displayName='High Failover Latency'" --project="${PROJECT_ID}" --format='value(name)' | grep -q .; then
  NOTIFICATION_CHANNELS_JSON=$(build_notification_channels_json)
  cat > /tmp/alert1.json << 'ALERT_JSON'
{
  "displayName": "High Failover Latency",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Failover > 4.5 seconds",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/failover_latency_ms\" AND resource.type=\"global\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 4500,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "notificationChannels": __NOTIFICATION_CHANNELS__,
  "severity": "WARNING"
}
ALERT_JSON

  sed -i "s|__NOTIFICATION_CHANNELS__|${NOTIFICATION_CHANNELS_JSON}|" /tmp/alert1.json
  
  gcloud monitoring policies create --policy-from-file=/tmp/alert1.json \
    --project="${PROJECT_ID}"
  
  ALERT_POLICY_COUNT=$((ALERT_POLICY_COUNT + 1))
fi

log_event "alert_policies_created" "success" "Created ${ALERT_POLICY_COUNT} alert policies"

# ============================================================================
# 5. Enable Metrics Export to BigQuery
# ============================================================================
echo "📊 Configuring BigQuery export..."

# Create log sink for credential rotation events
if ! gcloud logging sinks describe credential-rotation-bq-sink --project="${PROJECT_ID}" &>/dev/null; then
  gcloud logging sinks create credential-rotation-bq-sink \
    "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${AUDIT_DATASET}" \
    --log-filter='resource.type="cloud_run_job" AND jsonPayload.action="credential_rotation"' \
    --project="${PROJECT_ID}" 2>/dev/null
  
  log_event "bigquery_sink_created" "success" "credential rotation events sinking to BigQuery"
fi

# ============================================================================
# 6. Create SLA Tracker Query
# ============================================================================
echo "📈 Creating SLA tracking query..."

cat > scripts/monitoring/query-sla-compliance.sh << 'QUERY_SCRIPT'
#!/bin/bash
# Query Phase-4 SLA compliance (failover latency < 5 seconds)

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
DAYS_BACK="${1:-7}"

# Query: Calculate percentage of failovers < 5 seconds
bq query --use_legacy_sql=false \
  "SELECT 
     COUNTIF(latency_ms < 5000) as compliant_count,
     COUNT(*) as total_count,
     ROUND(100.0 * COUNTIF(latency_ms < 5000) / COUNT(*), 2) as compliance_percentage
   FROM \`${PROJECT_ID}.audit_logs.failover_events\`
   WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${DAYS_BACK} DAY)"
QUERY_SCRIPT

chmod +x scripts/monitoring/query-sla-compliance.sh

log_event "sla_query_created" "success" "SLA compliance query script deployed"

# ============================================================================
# COMPLETION
# ============================================================================

log_event "phase4_monitoring_deploy_complete" "success" "GCP monitoring infrastructure deployed"

echo ""
echo "✅ PHASE-4 MONITORING DEPLOYMENT COMPLETE"
echo ""
echo "📊 Dashboard: https://console.cloud.google.com/monitoring/dashboards"
echo "🚨 Alerts: https://console.cloud.google.com/monitoring/alerting"
echo "📈 Metrics Explorer: https://console.cloud.google.com/monitoring/metrics-explorer"
echo ""
echo "Audit log: ${AUDIT_LOG}"
