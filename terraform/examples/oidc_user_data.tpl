#!/usr/bin/env bash
set -euo pipefail
# Example user-data snippet for cloud instance bootstrap (prototype)
# This script assumes the machine can obtain an OIDC JWT (via metadata or other provider)
# and that Vault is configured with an OIDC auth method and a role 'runner-role'.

VAULT_ADDR="${vault_addr}"
ROLE="runner-role"
RUNNER_DIR="/opt/actions-runner"
REPO_URL="${repo_url}"
RUNNER_NAME="${runner_name}"
SECRET_PATH="secret/data/ci/self-hosted/${secret_key}"

# Example: obtain JWT from metadata service (provider-specific) — replace with your provider's flow
# AWS/GCP/Azure have different endpoints, this is a placeholder
# OIDC_JWT=$(curl -s "<OIDC_METADATA_ENDPOINT>")
# For manual testing, you may set VAULT_OIDC_JWT env before running bootstrap.

export VAULT_ADDR
export VAULT_OIDC_ROLE="$ROLE"

# Caller could implement provider-specific JWT retrieval here
# For now, expect the JWT to be injected via the environment variable VAULT_OIDC_JWT

# Get a Vault client token using the OIDC JWT
VAULT_TOKEN=$(scripts/ci/vault_oidc_auth.sh --role "$ROLE" --vault-addr "$VAULT_ADDR")
export VAULT_TOKEN

# Retrieve the runner registration token from Vault
REG_TOKEN=$(scripts/ci/get-runner-token.sh "$SECRET_PATH" --vault-addr "$VAULT_ADDR")

# Bootstrap the runner (assumes runner binary archive is present or will be downloaded)
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download and extract runner if not present (example)
if [ ! -f config.sh ]; then
  curl -sSL "https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz" -o runner.tar.gz
  tar xzf runner.tar.gz
  rm -f runner.tar.gz
fi

./config.sh --unattended --url "$REPO_URL" --token "$REG_TOKEN" --name "$RUNNER_NAME"
# Install as service and start
sudo ./svc.sh install
sudo ./svc.sh start

