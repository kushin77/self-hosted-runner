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
