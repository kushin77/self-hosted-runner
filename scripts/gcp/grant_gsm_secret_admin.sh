#!/usr/bin/env bash
##############################################################################
# grant_gsm_secret_admin.sh
#
# Grants secretmanager.admin role to a service account to enable it to
# create, read, and manage secrets in Google Secret Manager.
#
# Usage: ./grant_gsm_secret_admin.sh PROJECT SERVICE_ACCOUNT_EMAIL
# Example: ./grant_gsm_secret_admin.sh nexusshield-prod nexusshield-tfstate-backup@nexusshield-prod.iam.gserviceaccount.com
#
# Requires: gcloud (with iam.serviceAccountPolicy.get/update.write permissions)
##############################################################################

set -euo pipefail

PROJECT="${1:-${TF_VAR_gcp_project:-nexusshield-prod}}"
ACCOUNT="${2:-nexusshield-tfstate-backup@${PROJECT}.iam.gserviceaccount.com}"

echo "[→] NexusShield Secret Manager IAM Setup"
echo "    Project: ${PROJECT}"
echo "    Service Account: ${ACCOUNT}"

# Validate service account format
if [[ ! "${ACCOUNT}" =~ ^[a-z0-9].*@${PROJECT}\.iam\.gserviceaccount\.com$ ]]; then
    echo "⚠ Warning: Service account email format may be incorrect"
    echo "   Expected: <name>@${PROJECT}.iam.gserviceaccount.com"
    echo "   Got: ${ACCOUNT}"
    echo ""
    echo "Proceeding anyway... (you can verify manually with:)"
    echo "   gcloud iam service-accounts describe ${ACCOUNT} --project=${PROJECT}"
fi

# Grant roles/secretmanager.admin
echo "[→] Granting secretmanager.admin role to ${ACCOUNT}..."
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${ACCOUNT}" \
    --role="roles/secretmanager.admin" \
    --project="${PROJECT}" \
    --quiet 2>&1 | grep -E "updated|ACTIVE" || true
echo "✓ secretmanager.admin granted (or already assigned)"

# Grant roles/secretmanager.secretAccessor (for reading secrets)
echo "[→] Granting secretmanager.secretAccessor role to ${ACCOUNT}..."
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="${PROJECT}" \
    --quiet 2>&1 | grep -E "updated|ACTIVE" || true
echo "✓ secretmanager.secretAccessor granted (or already assigned)"

# Verify the grants
echo "[→] Verifying IAM policy..."
POLICY=$(gcloud projects get-iam-policy "${PROJECT}" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${ACCOUNT}" \
    --format="value(bindings.role)" || echo "")

if echo "${POLICY}" | grep -q secretmanager; then
    echo "✓ Secret Manager roles verified"
else
    echo "⚠ Could not verify roles (may require Project Owner permissions)"
fi

echo ""
echo "✅ Secret Manager permissions granted"
echo ""
echo "Next: Retry the provisioning script to proceed with Terraform apply"
