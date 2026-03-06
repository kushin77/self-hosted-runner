#!/usr/bin/env bash
set -euo pipefail

# nuke_restore_dry_run.sh
# Non-destructive dry-run simulator for nuke -> restore flow.
# - Scans repository for destructive commands and scripts
# - Runs Terraform destroy plan (safe) and exports list of resources that WOULD be destroyed
# - Collects candidate restore actions and safety checks
# - Produces a JSON report under ./dry-run-report.json

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT="$ROOT_DIR/dry-run-report.json"
TF_DIR="$ROOT_DIR/terraform"

TMP_DIR="$(mktemp -d)"
FINDINGS_FILE="$TMP_DIR/findings.txt"
DRYRUN_SCRIPTS_FILE="$TMP_DIR/dryrun-scripts.txt"
TF_ADDRESSES_FILE="$TMP_DIR/tf-addresses.txt"

EXCLUDES=(--exclude-dir=.git --exclude-dir=build --exclude-dir=node_modules --exclude-dir=actions-runner/_work --exclude-dir=actions-runner/externals)

echo "scan_timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REPORT"

# Find destructive patterns (best-effort) but avoid noisy folders
echo "Scanning repository for destructive patterns (grep) ..."
grep -RInE "rm -rf|terraform destroy|kubectl delete|wipefs|sudo rm -rf|reboot|shutdown|destroy-cluster|\bnuke\b|tear down|teardown" "${ROOT_DIR}" "${EXCLUDES[@]}" || true > "$FINDINGS_FILE"

echo "Destructive findings:" >> "$REPORT"
sed 's/"/\\"/g' "$FINDINGS_FILE" >> "$REPORT"

# Terraform: run safe destroy plan if terraform exists
echo "" >> "$REPORT"
echo "terraform:" >> "$REPORT"
if [ -d "$TF_DIR" ]; then
  pushd "$TF_DIR" >/dev/null || true
  if command -v terraform >/dev/null 2>&1; then
    echo "  terraform_present: true" >> "$REPORT"
    echo "  running terraform init and plan -destroy (non-destructive) ..." >> "$REPORT"
    terraform init -input=false >/dev/null 2>&1 || true
    terraform plan -destroy -out=destroy-plan -input=false >/dev/null 2>&1 || true
    if [ -f destroy-plan ]; then
      if command -v terraform >/dev/null 2>&1; then
        terraform show -json destroy-plan > "$TMP_DIR/destroy-plan.json" 2>/dev/null || true
        if command -v jq >/dev/null 2>&1 && [ -s "$TMP_DIR/destroy-plan.json" ]; then
          jq -r '.resource_changes[]?.address' "$TMP_DIR/destroy-plan.json" | sed '/^$/d' > "$TF_ADDRESSES_FILE" || true
          echo "  destroy_plan_resources:" >> "$REPORT"
          sed 's/"/\\"/g' "$TF_ADDRESSES_FILE" >> "$REPORT"
        else
          echo "  destroy_plan: (created but jq not available to parse)" >> "$REPORT"
        fi
      fi
    else
      echo "  destroy_plan_available: false" >> "$REPORT"
    fi
  else
    echo "  terraform_present: false (terraform CLI missing)" >> "$REPORT"
  fi
  popd >/dev/null || true
else
  echo "  terraform_present: false (no terraform directory)" >> "$REPORT"
fi

# Find scripts that mention dry-run flags
echo "" >> "$REPORT"
echo "dry_run_capable_scripts:" >> "$REPORT"
grep -RInE "--dry-run|DRY_RUN|--noop|--plan" "${ROOT_DIR}" "${EXCLUDES[@]}" || true > "$DRYRUN_SCRIPTS_FILE"
sed 's/"/\\"/g' "$DRYRUN_SCRIPTS_FILE" >> "$REPORT"

# Posture checks
echo "" >> "$REPORT"
echo "posture_checks:" >> "$REPORT"
if [ -d "$TF_DIR" ] && grep -R "backend \"s3\"" "$TF_DIR" >/dev/null 2>&1; then
  echo "  state_backend_configured: true" >> "$REPORT"
else
  echo "  state_backend_configured: false" >> "$REPORT"
fi

if grep -RInE "pause:|read -p|read -r" "${ROOT_DIR}" "${EXCLUDES[@]}" >/dev/null 2>&1; then
  echo "  has_interactive_prompts: true" >> "$REPORT"
else
  echo "  has_interactive_prompts: false" >> "$REPORT"
fi

echo "" >> "$REPORT"
echo "summary:" >> "$REPORT"
echo "  note: This is a non-destructive simulation. No destructive actions were executed." >> "$REPORT"

echo "Dry-run report generated at: $REPORT"
echo "Temporary files are in: $TMP_DIR"

exit 0
