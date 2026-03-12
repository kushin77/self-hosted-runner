#!/usr/bin/env bash
set -euo pipefail

: ${REGISTRATION_TOKEN:?Need REGISTRATION_TOKEN (from GitLab Project → Settings → CI/CD → Runners) }
GITLAB_URL=${GITLAB_URL:-"https://gitlab.com/"}
RUNNER_DESCRIPTION=${RUNNER_DESCRIPTION:-"self-hosted-runner"}
RUNNER_TAGS=${RUNNER_TAGS:-"automation,primary"}

echo "== Installing GitLab Runner package (Debian/Ubuntu) =="
if ! command -v gitlab-runner >/dev/null 2>&1; then
  curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
  sudo apt-get update
  sudo apt-get install -y gitlab-runner
else
  echo "gitlab-runner already installed"
fi

echo "== Registering GitLab Runner (non-interactive) =="
sudo gitlab-runner register \
  --non-interactive \
  --url "${GITLAB_URL}" \
  --registration-token "${REGISTRATION_TOKEN}" \
  --executor "shell" \
  --description "${RUNNER_DESCRIPTION}" \
  --tag-list "${RUNNER_TAGS}" \
  --run-untagged "false" \
  --locked "false"

echo "== Enabling and starting gitlab-runner service =="
sudo systemctl enable --now gitlab-runner

echo "== Verifying runner =="
sudo gitlab-runner verify

echo "Runner registration complete. Check Project → Settings → CI/CD → Runners to confirm online status."
