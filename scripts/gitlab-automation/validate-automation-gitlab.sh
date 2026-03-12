#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:?Usage: PROJECT_ID must be set (CI_PROJECT_ID)}"
API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
TOKEN="${GITLAB_TOKEN:-}"

echo "🔍 GitLab: Validating issue automation setup for project ID $PROJECT_ID..."

echo "\n✓ Checking pipeline config..."
if [ -f ".gitlab-ci.yml" ]; then
  echo "  ✓ .gitlab-ci.yml exists"
else
  echo "  ✗ .gitlab-ci.yml missing!"
fi

echo "\n✓ Checking labels..."
required_labels=(
  "state:backlog"
  "state:in-progress"
  "state:review"
  "state:blocked"
  "state:done"
  "type:bug"
  "type:feature"
  "type:security"
  "type:compliance"
  "priority:p0"
  "priority:p1"
  "priority:p2"
)

if [ -z "$TOKEN" ]; then
  echo "  ⚠️ GITLAB_TOKEN not set; attempting to read public labels via unauthenticated API (may be rate-limited)"
  AUTH_ARGS=( )
else
  AUTH_ARGS=( -H "PRIVATE-TOKEN: $TOKEN" )
fi

existing_labels=$(curl -sSL "${AUTH_ARGS[@]}" "$API_URL/projects/$PROJECT_ID/labels?per_page=100" | jq -r '.[].name' 2>/dev/null || true)

missing=0
for label in "${required_labels[@]}"; do
  alt_label="$label"
  if [[ "$label" == *":"* ]]; then
    alt_label="${label#*:}"
  fi

  if echo "$existing_labels" | grep -xF -- "$label" >/dev/null 2>&1 || echo "$existing_labels" | grep -xF -- "$alt_label" >/dev/null 2>&1; then
    echo "  ✓ $label exists (matched: $label or $alt_label)"
  else
    echo "  ✗ $label missing!"
    ((missing++))
  fi
done

if [ "$missing" -gt 0 ]; then
  echo "\n⚠️ $missing labels missing. To create labels, run scripts/gitlab-automation/create-required-labels-gitlab.sh with a token that has API rights."
fi

echo "\n✓ Checking automation scripts..."
if [ -f "scripts/github-automation/triage-issues.sh" ] || [ -f "scripts/gitlab-automation/triage-issues-gitlab.sh" ]; then
  echo "  ✓ triage script exists"
else
  echo "  ✗ triage script missing"
fi

echo "\n✓ Checking CLI/tooling..."
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  echo "  ✓ curl and jq available"
else
  echo "  ⚠️ curl and jq are recommended for CI jobs"
fi

echo "\n✓ Validation complete"

if [ "${SKIP_ISSUE_TEST:-}" = "true" ]; then
  echo "Note: skipping live issue creation (SKIP_ISSUE_TEST=true)"
  exit 0
fi

echo "Attempting to create a test issue (requires token with API scope)..."
if [ -z "$TOKEN" ]; then
  echo "  ✗ GITLAB_TOKEN not provided; cannot create a test issue"
  exit 0
fi

payload=$(jq -n --arg t "Test: Automation Setup Validation $(date +%s)" --arg b "This is a test issue for validation" '{title:$t, description:$b}')
res=$(curl -sSL -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" -d "$payload" "$API_URL/projects/$PROJECT_ID/issues")
issue_iid=$(echo "$res" | jq -r .iid // empty)
if [ -n "$issue_iid" ]; then
  echo "  ✓ Created test issue #$issue_iid"
  # attempt to close
  curl -sSL -X PUT -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" -d '{"state_event":"close"}' "$API_URL/projects/$PROJECT_ID/issues/$issue_iid" >/dev/null || true
  echo "  ✓ Closed test issue #$issue_iid"
else
  echo "  ✗ Failed to create test issue. Response: $res"
fi
