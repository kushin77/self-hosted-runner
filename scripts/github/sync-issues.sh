#!/bin/bash
# sync-issues.sh — Create and manage GitHub issues #2273-#2277 for compliance tracking
# Requires: export auth_token="GITHUB_TOKEN" (admin PAT with repo scope)
# Usage: bash scripts/github/sync-issues.sh [--create|--close|--verify]

set -e

REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"

# Check token
if [ -z "$auth_token" ]; then
  echo "ERROR: auth_token not set. Export your GitHub admin PAT:"
  echo "  export auth_token=\"GITHUB_TOKEN\""
  echo ""
  echo "Token needed: Personal Access Token with 'repo' scope"
  echo "Create at: https://github.com/settings/tokens"
  exit 1
fi

# Verify token
echo "[*] Verifying GitHub token..."
user_response=$(curl -sS -H "Authorization: token $auth_token" https://api.github.com/user)
user_login=$(echo "$user_response" | jq -r '.login // empty')
if [ -z "$user_login" ]; then
  echo "ERROR: Token authentication failed."
  exit 1
fi
echo "✅ Authenticated as: $user_login"
echo ""

# Issue definitions
declare -A ISSUES=(
  [2273]="Framework Complete v1.0|closed|Go-live authorized and production deployment executed.|ops,deployment"
  [2274]="Monthly NO GitHub Actions Compliance|open|Verify ZERO GitHub Actions workflows and enforcement.|ops,security,monthly"
  [2275]="Monthly Credential Rotation & Validation|open|Validate GSM→Vault→KMS rotation success.|ops,security,monthly"
  [2276]="Monthly Audit Trail Compliance|open|Verify JSONL integrity, retention, immutability.|ops,compliance,monthly"
  [2277]="Team Training & Certification|open|Ensure team certified (80% exam pass).|ops,training,monthly"
)

# Function to create or update an issue
create_issue() {
  local issue_num=$1
  local title=$2
  local state=$3
  local body=$4
  local labels=$5
  
  echo "[*] Creating/updating issue #$issue_num: $title"
  
  # Try creating new issue
  response=$(curl -sS -w '\n%{http_code}' -X POST \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/issues" \
    -H "Authorization: token $auth_token" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -d "{
      \"title\": \"$title\",
      \"body\": \"$body\n\nLocal tracking file: docs/issues/$issue_num\",
      \"labels\": [$(echo $labels | tr ',' '\n' | sed 's/^/\"/' | sed 's/$/\"/' | paste -sd ',' -)]
    }")
  
  http_code=$(echo "$response" | tail -1)
  body_resp=$(echo "$response" | head -n -1)
  
  if [ "$http_code" = "201" ]; then
    echo "  ✅ Created (HTTP 201)"
  elif [ "$http_code" = "422" ]; then
    # Issue likely exists; update state instead
    echo "  → Issue exists; updating state to: $state"
    curl -sS -w '\n%{http_code}' -X PATCH \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/issues/$issue_num" \
      -H "Authorization: token $auth_token" \
      -H "Accept: application/vnd.github+json" \
      -d "{\"state\": \"$state\"}" > /dev/null
    echo "  ✅ Updated (HTTP 200)"
  else
    echo "  ⚠️  Response (HTTP $http_code)"
  fi
}

# Function to close an issue
close_issue() {
  local issue_num=$1
  
  echo "[*] Closing issue #$issue_num"
  
  response=$(curl -sS -w '\n%{http_code}' -X PATCH \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/issues/$issue_num" \
    -H "Authorization: token $auth_token" \
    -H "Accept: application/vnd.github+json" \
    -d '{"state":"closed"}')
  
  http_code=$(echo "$response" | tail -1)
  
  if [ "$http_code" = "200" ]; then
    echo "  ✅ Closed (HTTP 200)"
  else
    echo "  ⚠️  Response (HTTP $http_code)"
  fi
}

# Main action
ACTION=${1:---create}

case "$ACTION" in
  --create)
    echo "[*] Creating/updating GitHub issues #2273-#2277..."
    echo ""
    for issue_num in 2273 2274 2275 2276 2277; do
      IFS='|' read -r title state body labels <<< "${ISSUES[$issue_num]}"
      create_issue "$issue_num" "$title" "$state" "$body" "$labels"
    done
    ;;
  
  --close)
    echo "[*] Closing issues #2274-#2277 (keeping #2273 for reference)..."
    echo ""
    for issue_num in 2274 2275 2276 2277; do
      close_issue "$issue_num"
    done
    ;;
  
  --verify)
    echo "[*] Verifying GitHub issues #2273-#2277..."
    echo ""
    for issue_num in 2273 2274 2275 2276 2277; do
      response=$(curl -sS -H "Authorization: token $auth_token" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/issues/$issue_num")
      
      state=$(echo "$response" | jq -r '.state // "not found"')
      title=$(echo "$response" | jq -r '.title // "ERROR"')
      
      echo "→ #$issue_num: [$state] $title"
    done
    ;;
  
  *)
    echo "Usage: $0 [--create|--close|--verify]"
    echo ""
    echo "  --create   Create/update issues #2273-#2277"
    echo "  --close    Close issues #2274-#2277"
    echo "  --verify   Verify all issues exist and state"
    exit 1
    ;;
esac

echo ""
echo "✅ GitHub issues sync complete!"
