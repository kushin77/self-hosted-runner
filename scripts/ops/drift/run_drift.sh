#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/workspace/terraform/phase0-core"
OUTDIR="/workspace/drift-output"
mkdir -p "$OUTDIR"
cd "$WORKDIR"

# init
terraform init -input=false -backend=false >/dev/null 2>&1 || true

# plan
PLAN_FILE="$OUTDIR/tfplan"
PLAN_OUTPUT="$OUTDIR/plan.txt"

terraform plan -input=false -out="$PLAN_FILE" 2>&1 | tee "$PLAN_OUTPUT"

# show human-readable plan
terraform show -no-color "$PLAN_FILE" > "$OUTDIR/plan.pretty.txt" || true

# If SLACK_WEBHOOK is provided, post a summary
if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
  SUMMARY=$(head -c 8000 "$PLAN_OUTPUT" | sed 's/"/\\"/g' | sed 's/`/\`/g')
  PAYLOAD="{\"text\":\"Terraform drift check for ${PROJECT_ID:-project}: \n\n\`\`\`$SUMMARY\`\`\`\"}"
  curl -s -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$SLACK_WEBHOOK" || true
fi

echo "Drift check completed. Outputs: $OUTDIR"
