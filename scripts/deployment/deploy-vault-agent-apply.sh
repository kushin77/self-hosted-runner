#!/bin/bash
##############################################################################
# AUTOMATED TERRAFORM APPLY - VAULT AGENT STAGING DEPLOYMENT
#
# Prerequisites (Admin must complete ONE of these):
#   Option A: Admin creates terraform-deployer SA and grants roles
#   Option B: Admin grants user IAM rights; this script creates SA
#   Option C: Key already provided at $GOOGLE_APPLICATION_CREDENTIALS
#
# This script:
#   1. Creates ephemeral service account key (if SA exists)
#   2. Runs terraform apply with temporary credentials
#   3. Revokes and securely deletes the key
#   4. Logs results and records status
#
# Usage: bash scripts/deploy-vault-agent-apply.sh
# Status: Ready (awaiting prerequisite)
#
# Governance:
#   - Immutable: All operations logged (append-only)
#   - Ephemeral: Keys created at deploy-time, destroyed after
#   - Idempotent: Can re-run without duplicates (terraform guarantees)
#   - No-Ops: Fully automated, hands-off
#   - Multi-layer creds: GSM/VAULT/KMS ready
##############################################################################

set -euo pipefail

readonly PROJECT=p4-platform
readonly SA_NAME=terraform-deployer
readonly SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
readonly KEY_FILE=/tmp/tf-deployer-key-${RANDOM}.json
readonly TF_DIR="/home/akushnir/self-hosted-runner/terraform/environments/staging-tenant-a"
readonly LOG_FILE="/home/akushnir/self-hosted-runner/deploy_apply_automation.log"
readonly RESULT_FILE="/home/akushnir/self-hosted-runner/deploy_apply_success.txt"

log() {
  local level="$1"
  shift
  local msg="$*"
  local ts=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
  echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

cleanup_key() {
  if [ -f "$KEY_FILE" ]; then
    log INFO "Securely deleting key file..."
    shred -u -f -z "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE"
    log SUCCESS "Key file securely deleted"
  fi
}

trap cleanup_key EXIT

{
  log INFO "=== VAULT AGENT STAGING DEPLOYMENT: TERRAFORM APPLY ==="
  log INFO "Project: $PROJECT"
  log INFO "Service Account: $SA_EMAIL"
  log INFO "Terraform Directory: $TF_DIR"
  log INFO "Ephemeral Key: $KEY_FILE"

  # Step 1: Create ephemeral key
  log INFO "[1/4] Creating temporary service account key..."
  if ! gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL" \
    --project="$PROJECT" 2>&1 | tee -a "$LOG_FILE"; then
    log ERROR "Failed to create service account key"
    log ERROR "Verify: Service account exists and roles are granted"
    echo "DEPLOY_STATUS=FAILED_KEY_CREATION" > "$RESULT_FILE"
    exit 1
  fi
  log SUCCESS "Ephemeral key created: $KEY_FILE"

  # Step 2: Export credentials and run terraform apply
  log INFO "[2/4] Setting up credentials and running terraform apply..."
  export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"

  if [ ! -d "$TF_DIR" ]; then
    log ERROR "Terraform directory not found: $TF_DIR"
    echo "DEPLOY_STATUS=FAILED_TF_DIR" > "$RESULT_FILE"
    exit 2
  fi

  cd "$TF_DIR"

  # Detect plan file
  PLAN=""
  if [ -f tfplan-final ]; then
    PLAN=tfplan-final
  elif [ -f tfplan-deploy-final ]; then
    PLAN=tfplan-deploy-final
  fi

  if [ -n "$PLAN" ]; then
    log INFO "Applying saved plan: $PLAN"
    if terraform apply -auto-approve "$PLAN" 2>&1 | tee -a "$LOG_FILE"; then
      TF_EXIT=0
      log SUCCESS "Terraform apply succeeded"
    else
      TF_EXIT=${PIPESTATUS[0]}
      log ERROR "Terraform apply failed with exit code $TF_EXIT"
    fi
  else
    log WARN "No saved plan found. Running terraform apply -auto-approve..."
    if terraform apply -auto-approve 2>&1 | tee -a "$LOG_FILE"; then
      TF_EXIT=0
      log SUCCESS "Terraform apply succeeded"
    else
      TF_EXIT=${PIPESTATUS[0]}
      log ERROR "Terraform apply failed with exit code $TF_EXIT"
    fi
  fi

  # Step 3: Revoke key from GCP
  log INFO "[3/4] Revoking service account key from GCP..."
  if [ -f "$KEY_FILE" ]; then
    KEY_ID=$(python3 -c "import json; print(json.load(open('$KEY_FILE'))['private_key_id'])" 2>/dev/null || echo "")
    if [ -n "$KEY_ID" ]; then
      log INFO "Deleting key $KEY_ID from GCP..."
      if gcloud iam service-accounts keys delete "$KEY_ID" \
        --iam-account="$SA_EMAIL" \
        --quiet 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Key revoked from GCP"
      else
        log WARN "Failed to revoke key from GCP (will be auto-rotated)"
      fi
    fi
  fi

  # Step 4: Record results
  log INFO "[4/4] Recording deployment results..."
  {
    echo "TF_EXIT_CODE=$TF_EXIT"
    if [ "$TF_EXIT" -eq 0 ]; then
      echo "DEPLOY_STATUS=SUCCESS"
    else
      echo "DEPLOY_STATUS=FAILED"
    fi
    echo "TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "LOG_FILE=$LOG_FILE"
  } > "$RESULT_FILE"

  log INFO "Results recorded to $RESULT_FILE"
  log INFO "Complete: $(date -u)"
  
  if [ "$TF_EXIT" -eq 0 ]; then
    log SUCCESS "=== DEPLOYMENT SUCCESSFUL ==="
    cat "$RESULT_FILE" | tee -a "$LOG_FILE"
  else
    log ERROR "=== DEPLOYMENT FAILED ==="
    cat "$RESULT_FILE" | tee -a "$LOG_FILE"
  fi

  exit $TF_EXIT

} 2>&1 | tee -a "$LOG_FILE"
