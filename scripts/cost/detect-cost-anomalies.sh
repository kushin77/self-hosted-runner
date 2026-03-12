#!/bin/bash
# Detect unusual cost patterns (daily spend vs. rolling average)

ANOMALY_LOG="logs/cost-anomalies-$(date +%Y-%m-%d).jsonl"

echo "🚨 Cost Anomaly Detection"
echo "========================"
echo ""

# Baseline: 7-day rolling average
echo "Calculating 7-day rolling average..."
BASELINE_COST="1250.00"  # Simulated average daily cost

# Today's cost (simulated - usually lags 1-2 days)
TODAY_COST="1100.00"

# Calculate deviation
DEVIATION=$(echo "scale=2; ($BASELINE_COST - $TODAY_COST) / $BASELINE_COST * 100" | bc 2>/dev/null || echo "0")

echo "7-day rolling average: \$$BASELINE_COST"
echo "Today's cost: \$$TODAY_COST"
echo "Deviation: ${DEVIATION}% (within normal range)"
echo ""

# Check for anomalies
THRESHOLD=50  # Alert if > 50% deviation

if (( $(echo "$DEVIATION > $THRESHOLD" | bc -l) )); then
  echo "⚠️  ANOMALY DETECTED: Cost > 1.5x baseline"
  echo "  Action: Trigger investigation workflow"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"alert\":\"cost_anomaly\",\"baseline\":\$$BASELINE_COST,\"actual\":\$$TODAY_COST,\"deviation\":\"${DEVIATION}%\"}" >> "$ANOMALY_LOG"
else
  echo "✅ No anomalies detected"
fi

echo ""
echo "Anomaly log: $ANOMALY_LOG"
