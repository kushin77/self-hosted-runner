#!/usr/bin/env bash
set -euo pipefail

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GITHUB_TOKEN missing; cannot post comments" >&2
  exit 2
fi

REPO="kushin77/self-hosted-runner"
COMMENT2623="Blocked: attempted automated creation of Cloud Build trigger 'gov-scan-trigger' failed due to GCP IAM permissions for the active account. Immutable runbook and artifacts added to the repo: governance/PRIVILEGED_TRIGGER_SETUP.md and governance/NEEDS_TRIGGER_CREATION.md. Action required: an administrator should either grant the active account the roles 'roles/cloudbuild.builds.editor' (or 'roles/cloudbuild.admin') and 'roles/secretmanager.secretAccessor', or run the runbook as a privileged admin. After creating the trigger, post the trigger name and first-run ID here and I will validate the first run and close this issue."

COMMENT2619="Enforcement tools merged to main; initial scan detected no violations. Added immutable artifacts and runbook for scheduled enforcement: governance/PRIVILEGED_TRIGGER_SETUP.md, governance/NEEDS_TRIGGER_CREATION.md, and infra/cloudbuild (Terraform). Cloud Build trigger creation is blocked by GCP IAM (see #2623). Once the trigger is created and first-run completes, I will post the scan results here."

post_comment() {
  local issue=$1
  local body=$2
  curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
    "https://api.github.com/repos/$REPO/issues/$issue/comments" \
    -d "$(jq -Rn --arg b "$body" '{body:$b}')" >/dev/null
}

add_label() {
  local issue=$1
  local label=$2
  curl -sS -X PATCH -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
    "https://api.github.com/repos/$REPO/issues/$issue" \
    -d "$(jq -n --argjson a "[\"$label\"]" '{labels:$a}')" >/dev/null
}

post_comment 2623 "$COMMENT2623"
add_label 2623 "governance/action-required" || true
post_comment 2619 "$COMMENT2619"

echo "Posted comments to issues 2623 and 2619 and labeled 2623"
