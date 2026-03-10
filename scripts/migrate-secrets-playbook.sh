#!/usr/bin/env bash
set -euo pipefail

# Playbook for migrating GitHub repository secrets to GSM/Vault/KMS
# Run as repo/org admin with access to secret backends.

REPO_OWNER=${1:-kushin77}
REPO_NAME=${2:-self-hosted-runner}

cat <<'EOF'
Migration playbook: migrating GitHub secrets to GSM and Vault

1) List GitHub repo secrets (run locally with GH auth):
   gh secret list --repo ${REPO_OWNER}/${REPO_NAME}

2) For each secret name, create equivalent in Google Secret Manager (GSM):
   # Example (admins must supply secret value from secure source):
   # echo "$SECRET_VALUE" | gcloud secrets create SECRET_NAME --data-file=- --replication-policy="automatic" --project=PROJECT_ID || \
   #   gcloud secrets versions add SECRET_NAME --data-file=- --project=PROJECT_ID

3) Or, store in Vault (example):
   # vault must be authenticated (VAULT_ADDR+VAULT_TOKEN)
   # vault kv put secret/${REPO_NAME}/SECRET_NAME value="$SECRET_VALUE"

4) After storing in secret backend, remove the GitHub Actions secret:
   gh secret remove SECRET_NAME --repo ${REPO_OWNER}/${REPO_NAME}

5) Update deployment scripts to fetch secrets at runtime using scripts/secret-fetch.sh

6) Validate staging deployment:
   bash scripts/direct-deploy.sh staging
   tail -n 50 logs/direct-deploy-staging-*.jsonl

7) When all secrets migrated and verified, remove remaining GitHub Actions workflows (already archived) and disable Actions in repo settings.
EOF

echo "Playbook created. Follow steps above as repo admin."
