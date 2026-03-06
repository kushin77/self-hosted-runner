#!/usr/bin/env bash
set -euo pipefail

# gitlab_set_variable.sh
# Sets a GitLab CI/CD variable at project or group scope via API.

usage(){
  cat <<EOF
Usage: GITLAB_API_URL=https://gitlab.example.com GITLAB_API_TOKEN=... \
  ./scripts/ci/gitlab_set_variable.sh --scope project --id 123 --key NAME --value VALUE --protected true --masked false

Options:
  --scope {project|group}
  --id    Project ID or Group ID
  --key   Variable key
  --value Variable value (use stdin when VALUE is '-').
  --protected true|false
  --masked true|false

Example:
  GITLAB_API_URL=https://gitlab.example.com GITLAB_API_TOKEN=tok ./scripts/ci/gitlab_set_variable.sh --scope project --id 42 --key GITHUB_MIRROR_SSH_KEY --value "$(cat id_rsa)" --protected true --masked true
EOF
}

if [ "${1:-}" = "--help" ]; then usage; exit 0; fi

SCOPE="project"
ID=""
KEY=""
VALUE=""
PROTECTED="true"
MASKED="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2;;
    --id) ID="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    --protected) PROTECTED="$2"; shift 2;;
    --masked) MASKED="$2"; shift 2;;
    *) echo "Unknown arg $1"; usage; exit 2;;
  esac
done

if [ -z "$ID" ] || [ -z "$KEY" ]; then
  echo "--id and --key are required"; usage; exit 2
fi

API_URL="${GITLAB_API_URL:-https://gitlab.example.com}"
TOKEN="${GITLAB_API_TOKEN:-}" 
if [ -z "$TOKEN" ]; then echo "GITLAB_API_TOKEN required in env"; exit 2; fi

if [ "$VALUE" = "-" ]; then VALUE=$(cat -); fi

if [ "$SCOPE" = "project" ]; then
  ENDPOINT="/api/v4/projects/${ID}/variables"
elif [ "$SCOPE" = "group" ]; then
  ENDPOINT="/api/v4/groups/${ID}/variables"
else
  echo "scope must be project or group"; exit 2
fi

echo "Setting variable $KEY at $SCOPE $ID"
curl -s --fail --request POST "${API_URL}${ENDPOINT}" \
  --header "PRIVATE-TOKEN: ${TOKEN}" \
  --form "key=${KEY}" \
  --form "value=${VALUE}" \
  --form "protected=${PROTECTED}" \
  --form "masked=${MASKED}" || {
    echo "Failed to set variable; attempting update"
    curl -s --fail --request PUT "${API_URL}${ENDPOINT}/${KEY}" \
      --header "PRIVATE-TOKEN: ${TOKEN}" \
      --form "value=${VALUE}" \
      --form "protected=${PROTECTED}" \
      --form "masked=${MASKED}" || { echo "Update failed"; exit 2; }
  }

echo "Variable $KEY set/updated."
