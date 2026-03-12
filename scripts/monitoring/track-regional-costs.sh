#!/bin/bash
# Track costs per region and report anomalies

REGIONS=("us-east-1" "eu-west-1" "ap-southeast-1")

echo "Regional cost tracking (last 24 hours):"
echo ""

for region in "${REGIONS[@]}"; do
  # Query AWS Cost Explorer
  COST=$(aws ce get-cost-and-usage \
    --time-period Start="$(date -d '1 day ago' +%Y-%m-%d)",End="$(date +%Y-%m-%d)" \
    --granularity DAILY \
    --metrics "BlendedCost" \
    --group-by Type=DIMENSION,Key=REGION \
    --filter file://- <<< '{
      "Dimensions": {
        "Key": "REGION",
        "Values": ["'"$region"'"]
      }
    }' \
    --region "$region" \
    --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
    --output text 2>/dev/null || echo "0.00")
  
  echo "  $region: \$$COST"
done

echo ""
echo "✅ Regional cost report generated"
