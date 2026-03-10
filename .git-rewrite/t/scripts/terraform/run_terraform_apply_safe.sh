#!/usr/bin/env bash
set -euo pipefail

# Safe wrapper to apply an existing terraform plan or create one then apply.
# Usage:
#   ./scripts/terraform/run_terraform_apply_safe.sh [plan-file]
#
# Behaviour:
# - If a plan file path is supplied, it will be used. Otherwise the script
#   will run `terraform plan -out=plan-out.tfplan` in `terraform/` and use that.
# - Creates a backup of current remote state via `terraform state pull` (local file).
# - Prompts for interactive confirmation before applying.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
DEFAULT_PLAN="$TF_DIR/plan-post-import-final.out"

PLAN_FILE="${1:-}"

if [ ! -d "$TF_DIR" ]; then
  echo "Error: terraform directory not found at $TF_DIR" >&2
  exit 2
fi

cd "$TF_DIR"

# Ensure terraform CLI available
if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform not found in PATH. Install terraform to proceed." >&2
  exit 2
fi

# Determine plan file
if [ -z "$PLAN_FILE" ]; then
  if [ -f "$DEFAULT_PLAN" ]; then
    PLAN_FILE="$DEFAULT_PLAN"
    echo "Using existing plan file: $PLAN_FILE"
  else
    echo "No plan file supplied and default plan not found; generating plan as plan-out.tfplan"
    terraform init -input=false
    terraform plan -out=plan-out.tfplan -input=false
    PLAN_FILE="$TF_DIR/plan-out.tfplan"
  fi
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file not found: $PLAN_FILE" >&2
  exit 2
fi

# Backup current state (best-effort)
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="terraform-state-backup-$TS.tfstate"
set +e
terraform state pull > "$BACKUP_FILE"
if [ $? -eq 0 ]; then
  echo "Saved current state to $BACKUP_FILE"
else
  echo "Warning: failed to pull remote state. Ensure credentials are available. Proceeding with caution." >&2
fi
set -e

# Show plan summary
echo "Plan file: $PLAN_FILE"
essh -n "$PLAN_FILE" || true

echo
echo "REVIEW the plan above. To proceed, type 'apply' (without quotes) and press Enter." 
read -r CONFIRM
if [ "$CONFIRM" != "apply" ]; then
  echo "Aborting: confirmation not provided." >&2
  exit 1
fi

# Run apply
echo "Running terraform apply (non-interactive)..."
terraform apply -input=false "$PLAN_FILE"

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "Terraform apply completed successfully."
else
  echo "Terraform apply exited with code $EXIT_CODE" >&2
fi

exit $EXIT_CODE
