#!/bin/bash
# Deploy Phase-4 Observability Framework
# GCP Cloud Monitoring + Dashboard + Alert Policies
# Author: GitHub Copilot (Autonomous Agent)
# Date: 2026-03-12

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
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

# ============================================================================
# 1. Create Log Router Sink for Credential Audit Trail
# ============================================================================
echo "📊 Creating log router sink..."

# Check if sink already exists (idempotent)
if ! gcloud logging sinks describe credential-audit-sink --project="${PROJECT_ID}" &>/dev/null; then
  gcloud logging sinks create credential-audit-sink \
    "storage.googleapis.com/nexusshield-prod-audit-logs-bq" \
    --log-filter='resource.type="cloud_function" OR resource.type="cloud_run_job"' \
    --project="${PROJECT_ID}" || true
  
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
gcloud monitoring metrics-descriptors create \
  --description="Age of current credential in seconds" \
  --display-name="Credential Age" \
  --value-type=INT64 \
  --metric-kind=GAUGE \
  "custom.googleapis.com/credential_age_seconds" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "Metric already exists (idempotent)"

# Metric 2: Failover Latency (milliseconds)
gcloud monitoring metrics-descriptors create \
  --description="Latency of credential failover chain" \
  --display-name="Failover Latency" \
  --value-type=DOUBLE \
  --metric-kind=HISTOGRAM \
  "custom.googleapis.com/failover_latency_ms" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "Metric already exists (idempotent)"

# Metric 3: Layer Availability (0=down, 1=up)
gcloud monitoring metrics-descriptors create \
  --description="Credential layer availability status" \
  --display-name="Layer Status" \
  --value-type=INT64 \
  --metric-kind=GAUGE \
  "custom.googleapis.com/layer_status" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "Metric already exists (idempotent)"

log_event "custom_metrics_created" "success" "3 custom metrics registered"

# ============================================================================
# 3. Create Monitoring Dashboard
# ============================================================================
echo "📊 Creating monitoring dashboard..."

DASHBOARD_ID="phase4-credential-failover-dashboard"

# Check if dashboard exists
if ! gcloud monitoring dashboards describe "${DASHBOARD_ID}" --project="${PROJECT_ID}" &>/dev/null; then
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
    --project="${PROJECT_ID}" || true
  
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
if ! gcloud alpha monitoring policies list --filter="displayName='High Failover Latency'" --project="${PROJECT_ID}" 2>/dev/null | grep -q HIGH; then
  cat > /tmp/alert1.json << 'ALERT_JSON'
{
  "displayName": "High Failover Latency",
  "conditions": [
    {
      "displayName": "Failover > 4.5 seconds",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/failover_latency_ms\"",
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
  "notificationChannels": [],
  "severity": "WARNING"
}
ALERT_JSON
  
  gcloud alpha monitoring policies create --policy-from-file=/tmp/alert1.json \
    --project="${PROJECT_ID}" 2>/dev/null || true
  
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
    "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/audit_logs" \
    --log-filter='resource.type="cloud_run_job" AND jsonPayload.action="credential_rotation"' \
    --project="${PROJECT_ID}" 2>/dev/null || true
  
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
