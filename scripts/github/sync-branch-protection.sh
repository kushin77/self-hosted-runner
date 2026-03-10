#!/bin/bash
# sync-branch-protection.sh — Apply branch protection to main and production branches
# Requires: export auth_token="GITHUB_TOKEN" (admin PAT with repo scope)
# Usage: bash scripts/github/sync-branch-protection.sh

set -e

REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"
BRANCHES=("main" "production")

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
  echo "ERROR: Token authentication failed. Check token and try again."
  echo "Response: $user_response"
  exit 1
fi
echo "✅ Authenticated as: $user_login"
echo ""

# Load protection payload
if [ ! -f /tmp/protect_update.json ]; then
  echo "ERROR: /tmp/protect_update.json not found."
  echo "Creating default protection payload..."
  cat > /tmp/protect_update.json << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate-policies-and-keda","Branch name lint"]
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
fi

echo "[*] Applying branch protections..."
echo ""

# Apply to each branch
for branch in "${BRANCHES[@]}"; do
  echo "→ Protecting branch: $branch"
  
  response=$(curl -sS -w '\n%{http_code}' -X PUT \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/branches/$branch/protection" \
    -H "Authorization: token $auth_token" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    --data @/tmp/protect_update.json)
  
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)
  
  if [ "$http_code" = "200" ]; then
    echo "  ✅ Success (HTTP 200)"
  else
    echo "  ❌ Failed (HTTP $http_code)"
    echo "  Response: $body"
  fi
done

echo ""
echo "[*] Verifying branch protections..."
echo ""

for branch in "${BRANCHES[@]}"; do
  echo "→ Verifying: $branch"
  
  response=$(curl -sS -w '\n%{http_code}' -H "Authorization: token $auth_token" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/branches/$branch/protection")
  
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)
  
  if [ "$http_code" = "200" ]; then
    echo "  ✅ Protected (HTTP 200)"
    enforce_admins=$(echo "$body" | jq -r '.enforce_admins // false')
    has_pr_review=$(echo "$body" | jq -r '.required_pull_request_reviews != null')
    echo "    • Enforce admins: $enforce_admins"
    echo "    • PR review required: $has_pr_review"
  else
    echo "  ⚠️  Not protected or error (HTTP $http_code)"
  fi
done

echo ""
echo "✅ Branch protection sync complete!"
echo ""
echo "Next: Sync GitHub issues with 'scripts/github/sync-issues.sh'"
