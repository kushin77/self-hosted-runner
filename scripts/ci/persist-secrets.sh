#!/usr/bin/env bash
set -euo pipefail

# Persist repository secrets using the GH CLI.
# Usage:
#   GITHUB_ADMIN_TOKEN=... REPO=owner/repo MINIO_ENDPOINT=... \
#     MINIO_ACCESS_KEY=... MINIO_SECRET_KEY=... MINIO_BUCKET=... \
#     VAULT_ADDR=... VAULT_NAMESPACE=... \
#     scripts/ci/persist-secrets.sh

: "${GITHUB_ADMIN_TOKEN:?GITHUB_ADMIN_TOKEN is required (short-lived admin token)}"
REPO=${REPO:-kushin77/self-hosted-runner}

: "${MINIO_ENDPOINT:?MINIO_ENDPOINT is required}"
: "${MINIO_ACCESS_KEY:?MINIO_ACCESS_KEY is required}"
: "${MINIO_SECRET_KEY:?MINIO_SECRET_KEY is required}"
: "${MINIO_BUCKET:?MINIO_BUCKET is required}"
: "${VAULT_ADDR:?VAULT_ADDR is required}"
: "${VAULT_NAMESPACE:?VAULT_NAMESPACE is required}"

printf '%s' "$GITHUB_ADMIN_TOKEN" | gh auth login --with-token

echo "Persisting secrets to repository: $REPO"
gh secret set MINIO_ENDPOINT --body "$MINIO_ENDPOINT" --repo "$REPO"
gh secret set MINIO_ACCESS_KEY --body "$MINIO_ACCESS_KEY" --repo "$REPO"
gh secret set MINIO_SECRET_KEY --body "$MINIO_SECRET_KEY" --repo "$REPO"
gh secret set MINIO_BUCKET --body "$MINIO_BUCKET" --repo "$REPO"
gh secret set VAULT_ADDR --body "$VAULT_ADDR" --repo "$REPO"
gh secret set VAULT_NAMESPACE --body "$VAULT_NAMESPACE" --repo "$REPO"

echo "All secrets persisted to $REPO"
