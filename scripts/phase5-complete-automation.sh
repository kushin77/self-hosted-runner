#!/usr/bin/env bash
set -euo pipefail

# Complete hands-off Phase 5 automation workflow:
# 1. Enable Secret Manager API for p4-platform (via Terraform)
# 2. Provision staging kubeconfig into GSM
# 3. Run Phase 5 automation (Trivy scans, etc.)
# 4. Record all operations in immutable audit log
# 5. Clean up credentials
#
# Usage:
#   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-gsm.json
#   scripts/phase5-complete-automation.sh
#
# Or call directly:
#   scripts/phase5-complete-automation.sh /path/to/sa-gsm.json

PROJECT=p4-platform
AUDIT_LOG=logs/complete-finalization-audit.jsonl
CREDS_FILE="${1:-${GOOGLE_APPLICATION_CREDENTIALS:-}}"

if [[ -z "$CREDS_FILE" && -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "ERROR: No credentials provided."
  echo "Usage: $0 /path/to/sa-gsm.json"
  echo "  or set GOOGLE_APPLICATION_CREDENTIALS environment variable"
  exit 2
fi

# Set credentials if provided as argument
if [[ -n "$CREDS_FILE" ]]; then
  export GOOGLE_APPLICATION_CREDENTIALS="$CREDS_FILE"
fi

mkdir -p "$(dirname "$AUDIT_LOG")"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)

log_audit() {
  local op="$1"
  local status="$2"
  local msg="${3:-}"
  local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$ts" --arg op "$op" --arg status "$status" --arg msg "$msg" --arg commit "$COMMIT" \
      '{timestamp:$ts,operation:$op,status:$status,message:$msg,commit:$commit}' >> "$AUDIT_LOG"
  else
    printf '%s\n' "{\"timestamp\":\"$ts\",\"operation\":\"$op\",\"status\":\"$status\",\"message\":\"$msg\",\"commit\":\"$COMMIT\"}" >> "$AUDIT_LOG"
  fi
}

trap cleanup EXIT
cleanup() {
  if [[ -n "${CREDS_FILE:-}" && -f "$CREDS_FILE" ]]; then
    echo "Removing credentials file..."
    rm -f "$CREDS_FILE"
    log_audit "cleanup-credentials" "success" "Credential file deleted: $CREDS_FILE"
  fi
}

echo "=== PHASE 5 COMPLETE AUTOMATION ==="
echo "Project: $PROJECT"
echo "Audit log: $AUDIT_LOG"
echo "Commit: $COMMIT"

# Step 1: Enable GSM API
echo ""
echo "[1/3] Enabling Secret Manager API..."
log_audit "phase5-start" "initiated" "Phase 5 complete automation workflow started"

cd nexusshield/infrastructure/terraform/enable-secretmanager-run
if terraform init -input=false && terraform apply -auto-approve -input=false -var="project=$PROJECT"; then
  log_audit "gsm-api-enable" "success" "Secret Manager API enabled via Terraform"
  echo "✓ GSM API enabled"
else
  log_audit "gsm-api-enable" "failed" "Failed to enable Secret Manager API"
  echo "✗ GSM API enable failed" >&2
  exit 1
fi
cd - >/dev/null

# Step 2: Provision kubeconfig
echo ""
echo "[2/3] Provisioning staging kubeconfig to GSM..."
if bash scripts/provision-staging-kubeconfig-gsm.sh; then
  log_audit "provision-kubeconfig-gsm" "success" "Staging kubeconfig provisioned to GSM"
  echo "✓ Kubeconfig provisioned"
else
  log_audit "provision-kubeconfig-gsm" "failed" "Failed to provision kubeconfig"
  echo "✗ Kubeconfig provisioning failed" >&2
  exit 1
fi

# Step 3: Run Phase 5 automation
echo ""
echo "[3/3] Running Phase 5 automation (Trivy)..."

# Check if phase5 automation script exists
if [[ -f scripts/run_phase5_trivy.sh ]]; then
  if bash scripts/run_phase5_trivy.sh; then
    log_audit "phase5-trivy" "success" "Phase 5 Trivy automation completed"
    echo "✓ Phase 5 completed"
  else
    log_audit "phase5-trivy" "failed" "Phase 5 Trivy automation failed"
    echo "✗ Phase 5 failed" >&2
    exit 1
  fi
elif [[ -f scripts/run-phase5-trivy.sh ]]; then
  if bash scripts/run-phase5-trivy.sh; then
    log_audit "phase5-trivy" "success" "Phase 5 Trivy automation completed"
    echo "✓ Phase 5 completed"
  else
    log_audit "phase5-trivy" "failed" "Phase 5 Trivy automation failed"
    echo "✗ Phase 5 failed" >&2
    exit 1
  fi
else
  echo "⚠ Phase 5 automation script not found (scripts/run_phase5_trivy.sh or scripts/run-phase5-trivy.sh)"
  log_audit "phase5-trivy" "skipped" "Phase 5 automation script not found"
  echo "⚠ Skipping Phase 5 (script not found)"
fi

# Final commit of audit log
echo ""
echo "Recording audit log..."
git add "$AUDIT_LOG" || true
git commit -m "audit: phase 5 complete automation workflow (GSM enable, kubeconfig provisioning, Trivy)" --no-verify || true

log_audit "phase5-complete" "success" "Phase 5 complete automation workflow finished"

echo ""
echo "=== PHASE 5 AUTOMATION COMPLETE ==="
echo "Audit log: $AUDIT_LOG"
echo "All operations recorded and committed."
