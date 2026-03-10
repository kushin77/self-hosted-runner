#!/usr/bin/env bash
set -euo pipefail

# Phase-2 Terraform runner
# - Tries GSM -> Vault -> GCE metadata for service account JSON
# - Runs `terraform apply "phase2.plan"` idempotently
# - Appends an immutable JSONL audit entry to `logs/terraform_phase2_runner_audit.jsonl`

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKDIR/terraform" || exit 2

AUDIT_LOG="$WORKDIR/logs/terraform_phase2_runner_audit.jsonl"
TMP_SA="/tmp/terraform-sa.json"

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log_audit() {
  local status="$1" method="$2" msg="$3"
  mkdir -p "$WORKDIR/logs"
  jq -n --arg ts "$(timestamp)" --arg status "$status" --arg method "$method" --arg msg "$msg" \
    '{timestamp:$ts,status:$status,method:$method,message:$msg}' >> "$AUDIT_LOG"
}

cleanup() {
  rm -f "$TMP_SA"
}
trap cleanup EXIT

obtain_from_gsm() {
  if command -v gcloud >/dev/null 2>&1; then
    if gcloud secrets versions access latest --secret=gcp-terraform-sa-key >/dev/null 2>&1; then
      echo "Obtaining service account key from GSM (gcloud)"
      gcloud secrets versions access latest --secret=gcp-terraform-sa-key > "$TMP_SA"
      export GOOGLE_APPLICATION_CREDENTIALS="$TMP_SA"
      return 0
    fi
  fi
  return 1
}

obtain_from_vault() {
  if command -v vault >/dev/null 2>&1; then
    if [ -n "${VAULT_ADDR:-}" ]; then
      set +e
      vault kv get -field=key secret/data/gcp/terraform-sa-key > "$TMP_SA" 2>/dev/null
      rc=$?
      set -e
      if [ $rc -eq 0 ] && [ -s "$TMP_SA" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$TMP_SA"
        return 0
      fi
    fi
  fi
  return 1
}

obtain_from_metadata() {
  # Try metadata server for GCE (no files written)
  if curl -s -m 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ >/dev/null 2>&1; then
    echo "Running on GCE; using metadata credentials (ADC from metadata)."
    # Rely on ADC; nothing to write
    return 0
  fi
  return 1
}

choose_credentials() {
  if obtain_from_gsm; then
    log_audit "ok" "gsm" "Used GSM service account key"
    return 0
  fi
  if obtain_from_vault; then
    log_audit "ok" "vault" "Used Vault service account key"
    return 0
  fi
  if obtain_from_metadata; then
    log_audit "ok" "metadata" "Using GCE metadata ADC"
    return 0
  fi
  log_audit "error" "none" "No credentials obtained"
  return 1
}

echo "Phase-2 runner starting: $(timestamp)"

if [ ! -f "phase2.plan" ]; then
  log_audit "error" "precheck" "phase2.plan not found"
  echo "phase2.plan not found in terraform/ - aborting"
  exit 2
fi

if ! choose_credentials; then
  echo "No credentials available (GSM|Vault|Metadata). Aborting."
  exit 3
fi

echo "Initializing Terraform (idempotent)"
terraform init -input=false -upgrade >/dev/null

echo "Applying plan: phase2.plan"
set +e
terraform apply -input=false "phase2.plan"
rc=$?
set -e

if [ $rc -eq 0 ]; then
  GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  log_audit "ok" "terraform_apply" "apply succeeded (commit:$GIT_COMMIT)"
  echo "Terraform apply completed successfully"
  exit 0
else
  log_audit "error" "terraform_apply" "apply failed (rc:$rc)"
  echo "Terraform apply failed with exit code $rc"
  exit $rc
fi
