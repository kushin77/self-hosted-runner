#!/usr/bin/env bash
set -euo pipefail

# scripts/check-runner-prereqs.sh
# Quick validation for self-hosted runner prerequisites.
# Usage: ./scripts/check-runner-prereqs.sh

commands=(gcloud aws gh kubectl kubeseal gpg mc jq)
missing=()

echo "Checking required CLIs..."
for cmd in "${commands[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $cmd"
  else
    echo "  ✗ $cmd (missing)"
    missing+=("$cmd")
  fi
done

echo
echo "Checking basic network connectivity tests..."

# GitHub API
if curl -sS --head https://api.github.com >/dev/null 2>&1; then
  echo "  ✓ api.github.com reachable"
else
  echo "  ✗ api.github.com unreachable (check egress to api.github.com)"
fi

# Optional checks if env vars present
if [[ -n "${VAULT_ADDR:-}" ]]; then
  if curl -sS --head "$VAULT_ADDR" >/dev/null 2>&1; then
    echo "  ✓ Vault ($VAULT_ADDR) reachable"
  else
    echo "  ✗ Vault ($VAULT_ADDR) unreachable"
  fi
fi

if [[ -n "${MINIO_ENDPOINT:-}" ]]; then
  if curl -sS --head "$MINIO_ENDPOINT" >/dev/null 2>&1; then
    echo "  ✓ MinIO endpoint ($MINIO_ENDPOINT) reachable"
  else
    echo "  ✗ MinIO endpoint ($MINIO_ENDPOINT) unreachable"
  fi
fi

echo
if [ ${#missing[@]} -gt 0 ]; then
  echo "Some required CLIs are missing: ${missing[*]}"
  exit 2
fi

echo "Runner prerequisites look OK (basic checks)."
exit 0
