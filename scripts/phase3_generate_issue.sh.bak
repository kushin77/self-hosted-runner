#!/usr/bin/env bash
set -euo pipefail

# Idempotent generator: creates or updates the Phase 3 provisioning issue
# Usage: REPO=owner/repo GITHUB_TOKEN=... ./scripts/phase3_generate_issue.sh

REPO=${REPO:-$(git config --get remote.origin.url || true)}
if [[ -z "$REPO" || "$REPO" == *"git@"* || "$REPO" == *"https:"* ]]; then
  # Normalize origin URL to owner/repo if running locally without REPO env
  ORIG=$(git config --get remote.origin.url || true)
  if [[ $ORIG == git@* ]]; then
    REPO=$(echo "$ORIG" | sed -E 's/.*:(.*)\.git/\1/')
  else
    REPO=$(echo "$ORIG" | sed -E 's#https?://[^/]+/([^/]+/[^/]+)(\.git)?#\1#')
  fi
fi

if [[ -z "$REPO" ]]; then
  echo "REPO not set and remote.origin.url not found. Export REPO=owner/repo or run inside a git repo."
  exit 1
fi

owner=${REPO%%/*}
repo=${REPO##*/}
title="Phase 3: Infrastructure Provisioning - GCP WIF & Vault Deployment"
body_file="/tmp/PHASE3_READY_SUMMARY.txt"

cat > "$body_file" <<'EOF'
Phase 3: Infrastructure Provisioning - Ready to Execute

This issue is generated/updated automatically by the repository on deployment.

Summary:
- Phase 1 & 2: Completed. Layer 3 (AWS KMS) operational.
- Phase 3: Provision GCP Workload Identity Federation and deploy Vault.

Steps (copy/paste):
1) cd infra && terraform init && terraform apply -var-file=terraform.tfvars
2) helm repo add hashicorp https://helm.releases.hashicorp.com
   helm install vault hashicorp/vault --namespace vault --create-namespace
3) gh workflow run secrets-orchestrator-multi-layer.yml --ref main
   sleep 180
   gh workflow run secrets-health-multi-layer.yml --ref main

This issue is idempotent: re-running this script will update the issue rather than create duplicates.

EOF

echo "Using repository: $owner/$repo"

auth_header=( -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" )

# Find existing issue with exact title
issues_json=$(curl -sS "https://api.github.com/repos/$owner/$repo/issues?state=all&per_page=100" "${auth_header[@]}")
issue_number=$(echo "$issues_json" | jq -r --arg TITLE "$title" '.[] | select(.title==$TITLE) | .number' | head -n1 || true)

if [[ -n "$issue_number" && "$issue_number" != "null" ]]; then
  echo "Updating existing issue #$issue_number"
  update_payload=$(jq -n --arg body "$(awk '{printf "%s\n", $0}' "$body_file")" '{body:$body}')
  curl -sS -X PATCH "https://api.github.com/repos/$owner/$repo/issues/$issue_number" \
    -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    -d "$update_payload" >/dev/null
  echo "Updated issue #$issue_number"
else
  echo "Creating new issue"
  create_payload=$(jq -n --arg title "$title" --arg body "$(awk '{printf "%s\n", $0}' "$body_file")" --argjson labels '["phase-3","infrastructure","provisioning","secrets-management","automation"]' '{title:$title, body:$body, labels:$labels}')
  created=$(curl -sS -X POST "https://api.github.com/repos/$owner/$repo/issues" \
    -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    -d "$create_payload")
  issue_number=$(echo "$created" | jq -r .number)
  echo "Created issue #$issue_number"
fi

# Optional: close open incident issues if CLOSE_INCIDENTS=true
if [[ "${CLOSE_INCIDENTS:-false}" == "true" ]]; then
  echo "Closing open incident issues with label 'incident' or title containing 'CRITICAL'"
  incidents=$(curl -sS "https://api.github.com/repos/$owner/$repo/issues?state=open&labels=incident&per_page=100" "${auth_header[@]}")
  echo "$incidents" | jq -r '.[].number' | while read -r num; do
    echo "Closing issue #$num"
    curl -sS -X PATCH "https://api.github.com/repos/$owner/$repo/issues/$num" \
      -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
      -d '{"state":"closed"}' >/dev/null
    curl -sS -X POST "https://api.github.com/repos/$owner/$repo/issues/$num/comments" \
      -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
      -d "$(jq -n --arg b "Closed by automation: Phase 3 completed or re-run requested." '{body:$b}')" >/dev/null
  done
fi

echo "Done. Issue number: $issue_number"
