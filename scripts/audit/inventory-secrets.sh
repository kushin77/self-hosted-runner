#!/usr/bin/env bash
set -euo pipefail
# Inventory secrets across repo, workflows, and (optionally) GitHub repo secrets via gh CLI.
# Outputs JSON to secrets-inventory-<date>.json

OUT_FILE="secrets-inventory-$(date -u +%Y-%m-%d).json"
REPO_URL="$(git config --get remote.origin.url 2>/dev/null || true)"
OWNER_REPO=""
if [ -n "$REPO_URL" ]; then
  # try to parse git@github.com:owner/repo.git or https://github.com/owner/repo.git
  OWNER_REPO=$(echo "$REPO_URL" | sed -e 's#.*github.com[:/]\([^/]*\)/\([^/.]*\).*#\1/\2#') || true
fi

echo "{\n  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," > "$OUT_FILE"

# Repo secrets via gh
echo "  \"repo_secrets\": [] ," >> "$OUT_FILE"
if command -v gh >/dev/null 2>&1 && [ -n "$OWNER_REPO" ]; then
  if gh secret list --repo "$OWNER_REPO" --json name 2>/dev/null >/tmp/gh_secrets.json; then
    echo "  \"repo_secrets\": "$(jq -c '.' /tmp/gh_secrets.json | sed 's/\n/ /g')"," > /tmp/gh_secrets_out.json || true
    # merge: replace repo_secrets line
    sed -i '1s/^/{PLACEHOLDER}/' "$OUT_FILE"
    awk 'NR==1{print "{\n  \"generated_at\": \"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)'"\","} NR>1{print}' /tmp/gh_secrets_out.json > "$OUT_FILE"
  fi
fi

# Workflow embedded secrets
echo "  \"workflow_embedded\": [" >> "$OUT_FILE"
find .github/workflows -name '*.yml' -o -name '*.yaml' 2>/dev/null | while read -r f; do
  matches=$(grep -n "secrets\." -n "$f" || true)
  if [ -n "$matches" ]; then
    echo "    {\"file\": \"$f\", \"matches\": \"$(echo "$matches" | sed 's/"/\\"/g' | tr '\n' '\\n')\" }," >> "$OUT_FILE"
  fi
done
echo "  ]," >> "$OUT_FILE"

# Hardcoded candidates
echo "  \"hardcoded_candidates\": [" >> "$OUT_FILE"
git grep -I --line-number -E "(PASSWORD|API_KEY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|SECRET|TOKEN|PASSWORD=)" -- . 2>/dev/null | sed 's/"/\\"/g' | while read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  rest=$(echo "$line" | cut -d: -f2- | sed 's/"/\\"/g')
  echo "    {\"file\": \"$file\", \"context\": \"$rest\" }," >> "$OUT_FILE"
done
echo "  ]" >> "$OUT_FILE"

echo "}\n" >> "$OUT_FILE"

echo "Wrote inventory to $OUT_FILE"
