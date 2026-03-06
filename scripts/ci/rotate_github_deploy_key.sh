#!/usr/bin/env bash
set -euo pipefail

# rotate_github_deploy_key.sh
# Generates a new SSH keypair, uploads the public key as a deploy key to the GitHub backup repo,
# stores the private key in GitLab CI/CD protected variable via the `gitlab_set_variable.sh` helper,
# and optionally removes the previous deploy key from GitHub.

usage(){
  cat <<EOF
Usage: GITHUB_REPO=org/repo GITHUB_TOKEN=... GITLAB_API_URL=... GITLAB_API_TOKEN=... GROUP_ID=1 ./scripts/ci/rotate_github_deploy_key.sh

Environment variables:
  GITHUB_REPO        - target GitHub repo (owner/repo)
  GITHUB_TOKEN       - GitHub PAT with repo:public_repo or repo write access
  GITLAB_API_URL     - GitLab URL
  GITLAB_API_TOKEN   - GitLab API token to set CI variables
  GROUP_ID           - GitLab group id to set variable (or PROJECT_ID)
  VAR_KEY            - variable name to store private key (default: GITHUB_MIRROR_SSH_KEY)
  REMOVE_OLD_KEY_ID  - (optional) GitHub deploy key id to remove after creating new one

This script requires `curl`, `jq`, and `ssh-keygen` available on PATH.
EOF
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then usage; exit 0; fi

: ${GITHUB_REPO:?}
: ${GITHUB_TOKEN:?}
: ${GITLAB_API_URL:?}
: ${GITLAB_API_TOKEN:?}
: ${GROUP_ID:?}
VAR_KEY=${VAR_KEY:-GITHUB_MIRROR_SSH_KEY}

TMPDIR=$(mktemp -d)
cleanup(){ rm -rf "$TMPDIR"; }
trap cleanup EXIT

KEY_FILE="$TMPDIR/id_ed25519"
ssh-keygen -t ed25519 -C "mirror-$(date -u +%Y%m%dT%H%M%SZ)" -f "$KEY_FILE" -N "" >/dev/null

PUB_KEY=$(cat "${KEY_FILE}.pub")

echo "Uploading public key to GitHub as a deploy key for ${GITHUB_REPO}"
RESP=$(curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/${GITHUB_REPO}/keys \
  -d "$(jq -n --arg title "ci-mirror-$(date -u +%Y%m%dT%H%M%SZ)" --arg key "$PUB_KEY" '{title: $title, key: $key, read_only: false}'))")

NEW_KEY_ID=$(echo "$RESP" | jq -r '.id // empty')
if [ -z "$NEW_KEY_ID" ]; then
  echo "Failed to upload deploy key to GitHub: $RESP" >&2
  exit 2
fi

echo "New GitHub deploy key id: $NEW_KEY_ID"

echo "Storing private key into GitLab CI variable ${VAR_KEY} (group ${GROUP_ID})"
export GITLAB_API_URL="$GITLAB_API_URL"
export GITLAB_API_TOKEN="$GITLAB_API_TOKEN"
$(dirname "$0")/gitlab_set_variable.sh --scope group --id "$GROUP_ID" --key "$VAR_KEY" --value "$(cat "$KEY_FILE")" --protected true --masked true

if [ -n "${REMOVE_OLD_KEY_ID:-}" ]; then
  echo "Removing old GitHub deploy key id ${REMOVE_OLD_KEY_ID}"
  curl -s -X DELETE -H "Authorization: token ${GITHUB_TOKEN}" \
    https://api.github.com/repos/${GITHUB_REPO}/keys/${REMOVE_OLD_KEY_ID} || true
fi

echo "Rotation complete. New key id: $NEW_KEY_ID; private key stored as GitLab variable ${VAR_KEY}."
