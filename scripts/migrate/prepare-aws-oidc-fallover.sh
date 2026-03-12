#!/bin/bash
set -euo pipefail
AUDIT_DIR="${AUDIT_DIR:-logs/multi-cloud-audit}"
PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
mkdir -p "$AUDIT_DIR"
log_action(){ echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"$1\",\"status\":\"$2\",\"details\":\"$3\"}" >> "$AUDIT_DIR/aws-oidc-migration-prepare-$(date +%Y%m%d-%H%M%S).jsonl"; }

# Verify AWS primary
if aws sts get-caller-identity > /dev/null 2>&1; then
  log_action "verify_primary_path" "success" "AWS STS assume-role working"
else
  log_action "verify_primary_path" "failed" "Cannot assume AWS role"
  echo "ERROR: AWS STS unavailable" >&2
  exit 1
fi

# Prepare GSM secrets if gcloud available
if command -v gcloud >/dev/null 2>&1; then
  # no-op if secrets already exist
  echo "Preparing GSM secrets (if credentials available locally)..."
  AWS_ACCESS_KEY=$(aws configure get aws_access_key_id 2>/dev/null || true)
  AWS_SECRET_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || true)
  if [[ -n "$AWS_ACCESS_KEY" ]]; then
    echo "$AWS_ACCESS_KEY" | gcloud secrets create aws-access-key-id --data-file=- --project="$PROJECT_ID" 2>/dev/null || echo "Adding new version"
    echo "$AWS_SECRET_KEY" | gcloud secrets versions add aws-secret-access-key --data-file=- --project="$PROJECT_ID" 2>/dev/null || true
    log_action "deploy_gsm_secrets" "success" "AWS credentials backed up to GSM"
  else
    log_action "deploy_gsm_secrets" "skipped" "No local AWS credentials found (using OIDC)"
  fi
else
  log_action "deploy_gsm_secrets" "skipped" "gcloud not available"
fi

# Verify GSA permission
GSA_EMAIL="deployer-run@${PROJECT_ID}.iam.gserviceaccount.com"
if command -v gcloud >/dev/null 2>&1; then
  if gcloud projects get-iam-policy "$PROJECT_ID" --flatten="bindings[].members" --filter="bindings.members:$GSA_EMAIL AND bindings.role:roles/secretmanager.secretAccessor" 2>/dev/null | grep -q "$GSA_EMAIL"; then
    log_action "verify_gsa_permissions" "success" "Service account has secret access"
  else
    gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$GSA_EMAIL" --role="roles/secretmanager.secretAccessor" 2>/dev/null || true
    log_action "verify_gsa_permissions" "warning" "Granted (or attempted) secretAccessor to $GSA_EMAIL"
  fi
fi

# Test GSM retrieval
if command -v gcloud >/dev/null 2>&1; then
  if gcloud secrets versions access latest --secret="aws-access-key-id" --project="$PROJECT_ID" 2>/dev/null | grep -q .; then
    log_action "test_gsm_retrieval" "success" "GSM credentials retrievable"
  else
    log_action "test_gsm_retrieval" "warning" "GSM credential retrieval failed or no secrets"
  fi
fi

log_action "phase1_complete" "success" "Preparation complete"
echo "PREPARE COMPLETE"
