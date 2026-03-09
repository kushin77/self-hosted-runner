#!/usr/bin/env bash
set -euo pipefail
# Idempotent branch protection applier using GitHub API or gh cli
# Usage: apply-branch-protection.sh --repo owner/repo --branch main --token <GITHUB_TOKEN> [--required-checks "check1,check2"]

print_usage() {
  cat <<EOF
Usage: $0 --repo owner/repo --branch <branch> --token <GITHUB_TOKEN> [--required-checks "check1,check2"]

This script applies branch protection in an idempotent way. If `gh` CLI is present and authenticated,
it will prefer `gh api`; otherwise it falls back to curl using the provided token.
EOF
}

REPO=""
BRANCH="main"
GITHUB_TOKEN=""
REQUIRED_CHECKS="validate-policies-and-keda"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --token) GITHUB_TOKEN="$2"; shift 2;;
    --required-checks) REQUIRED_CHECKS="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1"; print_usage; exit 2;;
  esac
done

if [[ -z "$REPO" || -z "$GITHUB_TOKEN" ]]; then
  echo "--repo and --token are required" >&2
  print_usage
  exit 2
fi

IFS="," read -r -a CONTEXTS_ARRAY <<< "$REQUIRED_CHECKS"
CONTEXTS_JSON="$(printf '\"%s\",' "${CONTEXTS_ARRAY[@]}")"
CONTEXTS_JSON="[${CONTEXTS_JSON%,}]"

PAYLOAD=$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": $CONTEXTS_JSON
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null
}
EOF
)

API_URL="https://api.github.com/repos/$REPO/branches/$BRANCH/protection"

apply_with_gh() {
  echo "Applying branch protection via gh api..."
  printf '%s' "$PAYLOAD" | gh api --method PUT "$API_URL" -H "Accept: application/vnd.github+json" -F body=@- || return 1
}

apply_with_curl() {
  echo "Applying branch protection via curl..."
  printf '%s' "$PAYLOAD" | curl -sS -X PUT "$API_URL" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d @-
}

if command -v gh >/dev/null 2>&1; then
  if apply_with_gh; then
    echo "Branch protection applied (gh)."
    exit 0
  fi
fi

if apply_with_curl; then
  echo "Branch protection applied (curl)."
  exit 0
fi

echo "Failed to apply branch protection." >&2
exit 1
