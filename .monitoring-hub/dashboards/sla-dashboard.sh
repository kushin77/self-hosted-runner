#!/bin/bash
# SLA Dashboard - Display current SLA status
set -euo pipefail

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    SLA DASHBOARD (24h)                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get latest metrics
LATEST_METRICS=$(tail -1 .monitoring-hub/metrics/sla-metrics.jsonl 2>/dev/null || echo "{}")

AUTH_SLA=$(echo "$LATEST_METRICS" | jq -r '.auth_sla // "N/A"')
ROTATION_SLA=$(echo "$LATEST_METRICS" | jq -r '.rotation_sla // "N/A"')
TIMESTAMP=$(echo "$LATEST_METRICS" | jq -r '.timestamp // "N/A"')

# Display metrics
printf "┌──────────────────────────────────────────────────────────────┐\n"
printf "│ Metric              │ Current  │ Target   │ Status           │\n"
printf "├──────────────────────────────────────────────────────────────┤\n"
printf "│ Auth SLA            │ %6.2f%% │ 99.90%%  │ " "$AUTH_SLA"
[ $(echo "$AUTH_SLA >= 99.9" | bc) -eq 1 ] && printf "✓ PASS │\n" || printf "✗ FAIL │\n"
printf "│ Rotation SLA        │ %6.2f%% │ 100.00%% │ " "$ROTATION_SLA"
[ $(echo "$ROTATION_SLA >= 100" | bc) -eq 1 ] && printf "✓ PASS │\n" || printf "✗ FAIL │\n"
printf "│ Last Updated        │ %s │\n" "$TIMESTAMP"
printf "└──────────────────────────────────────────────────────────────┘\n"
echo ""

echo "📊 Detailed Metrics:"
echo "  Auth Success Rate: $(echo "$LATEST_METRICS" | jq -r '.auth_success // "0"') / $(echo "$LATEST_METRICS" | jq -r '.auth_total // "0"')"
echo "  Rotation Success: $(echo "$LATEST_METRICS" | jq -r '.rotation_success // "0"') / $(echo "$LATEST_METRICS" | jq -r '.rotation_attempts // "0"')"
echo ""
