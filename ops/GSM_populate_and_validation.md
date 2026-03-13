Ops GSM Population & Validation — Immediate Actions

Purpose
- Provide exact commands and validation steps for Ops to populate Google Secret Manager (GSM) with the real credentials that enable the automated daily run (credential-rotation-daily).

Prerequisites
- gcloud authenticated with the production project (nexusshield-prod)
- AWS CLI installed and configured locally for validation (but environment will use GSM at runtime)
- IAM permissions to add secret versions in GSM and to read secrets for validation

Commands (copy/paste and replace placeholders):

# 1) Set your project
PROJECT_ID=nexusshield-prod
gcloud config set project $PROJECT_ID

# 2) Add AWS Access Key ID
# Replace the quoted value with the real AWS access key id
gcloud secrets versions add aws-access-key-id \
  --data-file=<(echo "AKIA...YOUR_REAL_AWS_ACCESS_KEY_ID...") \
  --project=$PROJECT_ID

# 3) Add AWS Secret Access Key
gcloud secrets versions add aws-secret-access-key \
  --data-file=<(echo "YOUR_REAL_AWS_SECRET_ACCESS_KEY") \
  --project=$PROJECT_ID

# 4) (Optional) Add Vault Token if using Vault flows
# Only if you manage Vault tokens outside automation
gcloud secrets versions add VAULT_TOKEN \
  --data-file=<(echo "YOUR_REAL_VAULT_TOKEN") \
  --project=$PROJECT_ID

# 5) (Optional) Add Cloudflare API token if used
gcloud secrets versions add cloudflare-api-token \
  --data-file=<(echo "YOUR_REAL_CLOUDFLARE_API_TOKEN") \
  --project=$PROJECT_ID

Validation steps (run locally after adding secrets):

# Export values locally to run a quick STS check
export AWS_ACCESS_KEY_ID=$(gcloud secrets versions access latest --secret=aws-access-key-id --project=$PROJECT_ID)
export AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access latest --secret=aws-secret-access-key --project=$PROJECT_ID)

# Validate AWS STS identity
aws sts get-caller-identity --output json
# Expected: JSON with Account and Arn fields

# Validate Cloud Build can access secrets (dry check)
# Replace BUILD_ID with a temporary Cloud Build submission ID if needed
# Or run an ad-hoc Cloud Build that just lists secrets (example below)
cat > cloudbuild/validate-secrets-cloudbuild.yaml <<'CLOUDY'
steps:
- name: gcr.io/cloud-builders/gcloud
  entrypoint: bash
  args:
  - -c
  - |
    set -euo pipefail
    echo "Checking GSM access from Cloud Build..."
    gcloud secrets versions access latest --secret=aws-access-key-id --project=$PROJECT_ID || exit 2
    gcloud secrets versions access latest --secret=aws-secret-access-key --project=$PROJECT_ID || exit 2
    echo "GSM access OK"
CLOUDY

# Submit the small validation build (it won't modify anything)
gcloud builds submit --config=cloudbuild/validate-secrets-cloudbuild.yaml --project=$PROJECT_ID .

What to do after validation
- If `aws sts get-caller-identity` succeeds and the Cloud Build validation job shows "GSM access OK":
  - Close GitHub issue #2939 (AWS credentials populated)
  - (Optional) Close #2941 if Cloudflare token added
  - Monitor first scheduled run tomorrow at 00:00 UTC (or run a manual Cloud Build submit to kick it off early)

Manual early-run (optional)
# Trigger the production Cloud Build manually (will run rotation+inventory)
PROJECT_ID=nexusshield-prod
gcloud builds submit --config=cloudbuild/rotate-credentials-cloudbuild.yaml --project=$PROJECT_ID .

Notes & Safety
- Scripts in the repo default to dry-run mode; Cloud Build fetches secrets at runtime from GSM.
- Do NOT commit secrets to git. Use `gcloud secrets versions add` only.
- If branch protection prevents deleting deprecated workflows, create a small PR to remove the file and ask org admin to merge.

Contact
- If you need help: ping on-call ops or reply here and I will proceed with next verification steps.
