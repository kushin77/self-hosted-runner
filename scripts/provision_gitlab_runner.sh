#!/bin/bash
set -e

# Provision a GitLab group-level runner using the installed gitlab-runner binary.
# Requires:
# - PRIMARY_PLATFORM=gitlab (healthcheck will call this)
# - GITLAB_URL (default: https://gitlab.com)
# - GITLAB_REGISTRATION_TOKEN (or fetched from Vault via fetch_vault_secrets.sh)
# - Optional: RUNNER_NAME, TAGS

SCRIPTS_DIR="/home/akushnir/self-hosted-runner/scripts"
if [ -x "${SCRIPTS_DIR}/fetch_vault_secrets.sh" ]; then
  . "${SCRIPTS_DIR}/fetch_vault_secrets.sh" || true
fi

GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
REG_TOKEN="${GITLAB_REGISTRATION_TOKEN:-$GITLAB_REGISTRATION_TOKEN}"
RUNNER_NAME="${RUNNER_NAME:-eiq-gitlab-runner-$(hostname -s)}"
TAGS="${TAGS:-linux,self-hosted}"

if [ -z "$REG_TOKEN" ]; then
  echo "GITLAB_REGISTRATION_TOKEN not set; cannot register runner"
  exit 2
fi

if ! command -v gitlab-runner >/dev/null; then
  echo "gitlab-runner not installed. Please install gitlab-runner on this host."
  exit 2
fi

echo "Registering GitLab runner with description '$RUNNER_NAME' and tags '$TAGS'"
gitlab-runner register --non-interactive \
  --url "$GITLAB_URL" \
  --registration-token "$REG_TOKEN" \
  --executor shell \
  --description "$RUNNER_NAME" \
  --tag-list "$TAGS" \
  --run-untagged="true" --locked="false"

echo "GitLab runner registration attempted. Verify with 'sudo gitlab-runner verify' or check /etc/gitlab-runner/config.toml"
