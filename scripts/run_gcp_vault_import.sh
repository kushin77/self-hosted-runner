#!/usr/bin/env bash
set -euo pipefail

# Helper to import existing GCP Vault resources into Terraform state and
# run a targeted apply for module.gcp_vault. Designed to be idempotent and
# safe to run when provided with credentials (ADC or GSM-stored SA key).
#
# Usage (interactive ADC):
#   ./scripts/run_gcp_vault_import.sh
#
# Usage (non-interactive, secrets in GSM):
#   SECRET_PROJECT=gcp-eiq GCP_SA_SECRET=service-account-json \
#     AWS_SECRET_NAME=aws-creds ./scripts/run_gcp_vault_import.sh
#
# The script will:
# - Optionally fetch a GCP service-account JSON and export GOOGLE_APPLICATION_CREDENTIALS
# - Optionally fetch AWS creds and export AWS env vars
# - Create a short-lived temp Terraform workspace that only initializes the google provider
# - Run `terraform import` for known resources and then a targeted apply for `module.gcp_vault`

WORKDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TFDIR="$WORKDIR/terraform"
TMPDIR=$(mktemp -d /tmp/tf-gcp-vault-import.XXXX)
LOG=${LOG:-/tmp/tf_gcp_vault_import_auto.log}

echo "Starting GCP Vault import helper at $(date)" | tee "$LOG"

if [ -n "${SECRET_PROJECT:-}" ] && [ -n "${GCP_SA_SECRET:-}" ]; then
  echo "Fetching GCP SA JSON from GSM: $GCP_SA_SECRET (project=$SECRET_PROJECT)" | tee -a "$LOG"
  gcloud secrets versions access latest --secret="$GCP_SA_SECRET" --project="$SECRET_PROJECT" > "$TMPDIR/gcp_sa.json"
  export GOOGLE_APPLICATION_CREDENTIALS="$TMPDIR/gcp_sa.json"
  echo "Exported GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS" | tee -a "$LOG"
fi

if [ -n "${SECRET_PROJECT:-}" ] && [ -n "${AWS_SECRET_NAME:-}" ]; then
  echo "Fetching AWS creds from GSM: $AWS_SECRET_NAME (project=$SECRET_PROJECT)" | tee -a "$LOG"
  gcloud secrets versions access latest --secret="$AWS_SECRET_NAME" --project="$SECRET_PROJECT" > "$TMPDIR/aws_creds.json"
  # Expect JSON with AccessKeyId/SecretAccessKey/SessionToken or a simple env-style file
  if jq -e . >/dev/null 2>&1 <"$TMPDIR/aws_creds.json"; then
    AWS_ACCESS_KEY_ID=$(jq -r '.AccessKeyId // .access_key_id // .AWS_ACCESS_KEY_ID' "$TMPDIR/aws_creds.json")
    AWS_SECRET_ACCESS_KEY=$(jq -r '.SecretAccessKey // .secret_access_key // .AWS_SECRET_ACCESS_KEY' "$TMPDIR/aws_creds.json")
    AWS_SESSION_TOKEN=$(jq -r '.SessionToken // .session_token // .AWS_SESSION_TOKEN' "$TMPDIR/aws_creds.json")
  else
    # parse KEY=VAL lines
    eval "$(grep -E '^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)=' "$TMPDIR/aws_creds.json" | tr '\n' ';')"
  fi
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  echo "Exported AWS env vars" | tee -a "$LOG"
fi

export AWS_EC2_METADATA_DISABLED=true

cat > "$TMPDIR/main.tf" <<EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = { source = "hashicorp/google" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "gcp_vault" {
  source       = "$TFDIR/modules/gcp-vault"
  project_id   = var.project_id
  region       = var.region
  bucket_prefix = var.bucket_prefix
  github_repo  = var.github_repo
}

output "vault_sa_email" { value = module.gcp_vault.vault_service_account_email }
EOF

cat > "$TMPDIR/variables.tf" <<EOF
variable "project_id" { type = string }
variable "region" { type = string, default = "us-central1" }
variable "bucket_prefix" { type = string, default = "vault-data" }
variable "github_repo" { type = string, default = "elevatediq-ai/ElevatedIQ-Mono-Repo" }
EOF

pushd "$TMPDIR" > /dev/null
echo "Temp workspace: $TMPDIR" | tee -a "$LOG"
terraform init -input=false >> "$LOG" 2>&1 || true

echo "Running imports..." | tee -a "$LOG"
terraform import -input=false module.gcp_vault.google_kms_key_ring.vault_key_ring projects/${TF_VAR_project_id:-gcp-eiq}/locations/us-central1/keyRings/vault-unseal-ring >> "$LOG" 2>&1 || true
terraform import -input=false module.gcp_vault.google_kms_crypto_key.vault_unseal_key projects/${TF_VAR_project_id:-gcp-eiq}/locations/us-central1/keyRings/vault-unseal-ring/cryptoKeys/vault-unseal-key >> "$LOG" 2>&1 || true
terraform import -input=false module.gcp_vault.google_service_account.vault_sa projects/${TF_VAR_project_id:-gcp-eiq}/serviceAccounts/vault-admin-sa@${TF_VAR_project_id:-gcp-eiq}.iam.gserviceaccount.com >> "$LOG" 2>&1 || true
terraform import -input=false module.gcp_vault.google_storage_bucket.vault_storage ${TF_VAR_bucket_prefix:-vault-data}-${TF_VAR_project_id:-gcp-eiq} >> "$LOG" 2>&1 || true
terraform import -input=false module.gcp_vault.google_storage_bucket_iam_member.vault_storage_access "${TF_VAR_bucket_prefix:-vault-data}-${TF_VAR_project_id:-gcp-eiq} roles/storage.objectAdmin serviceAccount:vault-admin-sa@${TF_VAR_project_id:-gcp-eiq}.iam.gserviceaccount.com" >> "$LOG" 2>&1 || true
terraform import -input=false module.gcp_vault.google_kms_crypto_key_iam_member.vault_kms_access "projects/${TF_VAR_project_id:-gcp-eiq}/locations/us-central1/keyRings/vault-unseal-ring/cryptoKeys/vault-unseal-key roles/cloudkms.cryptoKeyEncrypterDecrypter serviceAccount:vault-admin-sa@${TF_VAR_project_id:-gcp-eiq}.iam.gserviceaccount.com" >> "$LOG" 2>&1 || true

echo "Planning and applying module.gcp_vault (targeted)..." | tee -a "$LOG"
terraform plan -input=false -out=plan-gcp-vault.out >> "$LOG" 2>&1 || true
terraform apply -input=false -target=module.gcp_vault -auto-approve >> "$LOG" 2>&1 || true

echo "Import run complete. See log: $LOG" | tee -a "$LOG"
popd > /dev/null

echo "Cleanup: temporary workspace at $TMPDIR (left for inspection)" | tee -a "$LOG"

exit 0
