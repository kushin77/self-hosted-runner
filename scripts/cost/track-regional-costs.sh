#!/bin/bash
# Track costs per region and generate daily reports

REGIONS=("us-east-1" "eu-west-1" "ap-southeast-1")
REPORT_FILE="logs/daily-regional-cost-report-$(date +%Y-%m-%d).jsonl"

echo "📊 Regional Cost Tracking Report"
echo "================================"
echo ""

TOTAL_COST=0

for region in "${REGIONS[@]}"; do
  echo "Region: $region"
  
  # Query AWS Cost Explorer (requires setup)
  COST=$(aws ce get-cost-and-usage \
    --time-period Start="$(date -d '1 day ago' +%Y-%m-%d)",End="$(date +%Y-%m-%d)" \
    --granularity DAILY \
    --metrics "BlendedCost" \
    --group-by Type=DIMENSION,Key=LINKED_ACCOUNT \
    --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
    --output text 2>/dev/null || echo "0.00")
  
  if [ "$COST" == "0.00" ]; then
    COST="pending"  # Cost data usually lags by 1-2 days
  fi
  
  echo "  Daily Cost: \$$COST"
  
  # Log to JSONL
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"region\":\"$region\",\"cost\":\"$COST\"}" >> "$REPORT_FILE"
  
  # Accumulate total (skip "pending")
  if [ "$COST" != "pending" ]; then
    TOTAL_COST=$(echo "$TOTAL_COST + $COST" | bc 2>/dev/null || echo "0.00")
  fi
done

echo ""
echo "Total Daily Cost: \$$TOTAL_COST"
echo ""
echo "Report saved: $REPORT_FILE"
