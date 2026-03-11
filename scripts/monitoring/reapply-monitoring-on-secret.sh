#!/usr/bin/env bash
# Idempotent helper: re-apply monitoring Terraform when real Slack webhook is provided
# Usage: ./reapply-monitoring-on-secret.sh [project]

set -euo pipefail

PROJECT=${1:-nexusshield-prod}
PLACEHOLDER="REPLACE_WITH_SLACK_WEBHOOK"
LOGDIR="${PWD}/logs/monitoring"
mkdir -p "$LOGDIR"
OUT="$LOGDIR/reapply-$(date -u +%FT%TZ).log"

echo "Checking slack-webhook secret in project $PROJECT" | tee "$OUT"
secret_value=$(gcloud secrets versions access latest --secret=slack-webhook --project="$PROJECT" 2>/dev/null || echo "")

if [ -z "$secret_value" ]; then
  echo "slack-webhook secret not found in GSM for project $PROJECT" | tee -a "$OUT"
  exit 0
fi

if [ "$secret_value" = "$PLACEHOLDER" ]; then
  echo "Secret is placeholder; skipping Terraform apply" | tee -a "$OUT"
  exit 0
fi

echo "Real Slack webhook detected; running Terraform apply in infra/terraform/monitoring" | tee -a "$OUT"
cd "$(git rev-parse --show-toplevel)"/infra/terraform/monitoring
terraform apply -auto-approve -input=false 2>&1 | tee -a "$OUT"

echo "Terraform apply complete" | tee -a "$OUT"

exit 0
