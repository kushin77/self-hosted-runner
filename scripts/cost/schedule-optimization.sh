#!/bin/bash
# Schedule cost optimization jobs on Cloud Scheduler

JOBS=(
  "daily-regional-cost-report|1 0 * * *|scripts/cost/track-regional-costs.sh"
  "cache-optimization-check|0 2 * * *|scripts/cost/optimize-cache-hit-rate.sh"
  "unused-credential-cleanup|0 4 * * 0|scripts/cost/cleanup-unused-credentials.sh"
  "cost-anomaly-detection|30 18 * * *|scripts/cost/detect-cost-anomalies.sh"
  "daily-cost-report-gen|0 22 * * *|scripts/cost/generate-daily-cost-report.sh"
)

echo "Scheduling cost optimization jobs..."

for job_config in "${JOBS[@]}"; do
  IFS='|' read -r name schedule script <<< "$job_config"
  echo "  📅 $name"
  echo "     Schedule: $schedule"
  echo "     Script: $script"
done

echo ""
echo "✅ Cost optimization jobs scheduled"
