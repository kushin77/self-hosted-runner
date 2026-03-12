#!/usr/bin/env bash
set -euo pipefail

# Dry-run orchestrator for migrating secrets to GSM/Vault/KMS.
# This script does not write secrets; it validates inputs and prints the commands that would run.

echo "DRY-RUN: validating migration steps"

echo "1) Check presence of required helper scripts"
for s in store_token_in_gsm.sh store_ssh_in_gsm.sh store_token_in_vault.sh store_ssh_in_vault.sh; do
  if [ -f "$(dirname "$0")/$s" ] || [ -f "$(dirname "$0")/$s" ]; then
    echo "  OK: $s"
  else
    echo "  MISSING: $s (if using Vault/KMS, ensure corresponding scripts exist)"
  fi
done

echo "\n2) Planned migrations (example invocations):"
cat <<'EOF'
# Store GitHub token into GSM:
# ./scripts/ops/store_token_in_gsm.sh --project nexusshield-prod --secret-name verifier-github-token --value "<GITHUB_TOKEN>" --member-sa verifier-manager@PROJECT.iam.gserviceaccount.com

# Store runner SSH private key into GSM:
# ./scripts/ops/store_ssh_in_gsm.sh --project nexusshield-prod --secret-name runner-ssh-key --file /path/to/runner_key --member-sa runner-manager@PROJECT.iam.gserviceaccount.com

# Upload audit trail to S3 (requires AWS creds available via env):
# S3_BUCKET=my-immutable-bucket S3_PREFIX=nexus-audit LOG_DIR=./reports ./scripts/ops/upload_jsonl_to_s3.sh
EOF

echo "\n3) Verifying that audit-trail.jsonl exists and is readable"
if [ -f audit-trail.jsonl ]; then
  echo "  OK: audit-trail.jsonl present, size: $(wc -c < audit-trail.jsonl) bytes"
else
  echo "  MISSING: audit-trail.jsonl — ensure audit entries are present before upload"
fi

echo "\nDry-run complete. To perform live migration, run the above commands with proper credentials."

exit 0
