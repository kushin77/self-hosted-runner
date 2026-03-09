#!/bin/bash
# SLA Tracking Metrics Collector
set -euo pipefail

METRICS_FILE=".monitoring-hub/metrics/sla-metrics.jsonl"
NOW=$(date -Iseconds)

# Authentication SLA (Target: 99.9%)
AUTH_SUCCESS_RATE=$(grep -o '"status":"success"' .deployment-audit/*.jsonl 2>/dev/null | wc -l)
AUTH_TOTAL=$(find .deployment-audit -name "*.jsonl" -exec wc -l {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
AUTH_SLA=$([ "$AUTH_TOTAL" -gt 0 ] && echo "scale=4; $AUTH_SUCCESS_RATE * 100 / $AUTH_TOTAL" | bc || echo "0")

# Rotation SLA (Target: 100%)
ROTATION_SUCCESS=$(grep -c '"event":"rotation_complete"' .operations-audit/*.jsonl 2>/dev/null || echo "0")
ROTATION_ATTEMPTS=$(grep -c '"event":"rotation_' .operations-audit/*.jsonl 2>/dev/null || echo "0")
ROTATION_SLA=$([ "$ROTATION_ATTEMPTS" -gt 0 ] && echo "scale=2; $ROTATION_SUCCESS * 100 / $ROTATION_ATTEMPTS" | bc || echo "100")

# Write metrics
jq -n \
  --arg timestamp "$NOW" \
  --arg auth_sla "$AUTH_SLA" \
  --arg rotation_sla "$ROTATION_SLA" \
  --arg auth_success "$AUTH_SUCCESS_RATE" \
  --arg auth_total "$AUTH_TOTAL" \
  --arg rotation_success "$ROTATION_SUCCESS" \
  --arg rotation_attempts "$ROTATION_ATTEMPTS" \
  '{
    timestamp: $timestamp,
    auth_sla: $auth_sla,
    rotation_sla: $rotation_sla,
    auth_success: $auth_success,
    auth_total: $auth_total,
    rotation_success: $rotation_success,
    rotation_attempts: $rotation_attempts
  }' >> "$METRICS_FILE"

echo "SLA metrics updated: Auth=$AUTH_SLA% Rotation=$ROTATION_SLA%"
