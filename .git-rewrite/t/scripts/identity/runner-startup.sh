#!/usr/bin/env bash
set -euo pipefail

# Runner startup wrapper - prototype
# 1) Try OIDC/Vault bootstrap to obtain registry credentials
# 2) Run registry login (docker) if credentials are present
# 3) Register runner with GitHub using config.sh and the retrieved token

VAULT_ADDR=${VAULT_ADDR:-}
VAULT_ROLE=${VAULT_ROLE:-}
TARGET_REGISTRY=${TARGET_REGISTRY:-registry-staging.example.com}

# Location where the helper script (vault-oidc-bootstrap.sh) will be fetched if not present
BOOTSTRAP_URL="https://raw.githubusercontent.com/kushin77/self-hosted-runner/main/scripts/identity/vault-oidc-bootstrap.sh"
BOOTSTRAP_PATH="/tmp/vault-oidc-bootstrap.sh"

if [[ ! -x "$BOOTSTRAP_PATH" ]]; then
  echo "Fetching bootstrapper from $BOOTSTRAP_URL"
  curl -fsSL "$BOOTSTRAP_URL" -o "$BOOTSTRAP_PATH"
  chmod +x "$BOOTSTRAP_PATH"
fi

# Run bootstrapper to populate registry credentials (exports VAULT_TOKEN and logs in docker)
if [[ -n "${VAULT_ADDR:-}" && -n "${VAULT_ROLE:-}" ]]; then
  echo "Running Vault OIDC bootstrapper"
  # The bootstrapper will perform docker login when successful
  VAULT_TOKEN=$("$BOOTSTRAP_PATH" && echo "$VAULT_TOKEN") || true
else
  echo "Vault OIDC not configured (VAULT_ADDR/VAULT_ROLE missing). Skipping bootstrapper."
fi

# Look for REG_TOKEN from environment or from a known file (e.g., /etc/runner/REG_TOKEN)
if [[ -z "${REG_TOKEN:-}" && -f /etc/runner/REG_TOKEN ]]; then
  REG_TOKEN=$(cat /etc/runner/REG_TOKEN)
fi

if [[ -z "${REG_TOKEN:-}" ]]; then
  echo "WARNING: REG_TOKEN is not set. The runner registration may fail until a token is provided."
fi

# Finally register runner (assumes config.sh is present in working dir)
if [[ -x ./config.sh ]]; then
  echo "Registering runner with GitHub"
  RUNNER_ALLOW_RUNASROOT=1 ./config.sh --url https://github.com/kushin77/self-hosted-runner --token "${REG_TOKEN:-}" --labels "environment:staging" || true
else
  echo "config.sh not found in working directory; ensure the runner bootstrap includes the GitHub runner binaries and config.sh"
fi
