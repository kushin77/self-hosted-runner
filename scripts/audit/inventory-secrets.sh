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

TMP_REPO="/tmp/inv_repo_secrets.json"
TMP_WORK="/tmp/inv_workflow.json"
TMP_HARD="/tmp/inv_hard.json"

echo "[]" > "$TMP_REPO"
echo "[]" > "$TMP_WORK"
echo "[]" > "$TMP_HARD"

if command -v gh >/dev/null 2>&1 && [ -n "$OWNER_REPO" ]; then
  if gh secret list --repo "$OWNER_REPO" --json name 2>/dev/null > /tmp/gh_secrets.json; then
    # convert to compact JSON array
    if command -v jq >/dev/null 2>&1; then
      jq -c '.[]' /tmp/gh_secrets.json | jq -s '.' > "$TMP_REPO"
    else
      cp /tmp/gh_secrets.json "$TMP_REPO"
    fi
  fi
fi

# Workflow embedded secrets
work_items=()
while IFS= read -r f; do
  matches=$(grep -n "secrets\." "$f" || true)
  if [ -n "$matches" ]; then
    # escape newlines
    esc=$(printf '%s' "$matches" | sed ':a;N;$!ba;s/"/\\"/g;s/\n/\\n/g')
    work_items+=("{\"file\": \"$f\", \"matches\": \"$esc\"}")
  fi
done < <(find .github/workflows -name '*.yml' -o -name '*.yaml' 2>/dev/null)

if [ ${#work_items[@]} -gt 0 ]; then
  printf '%s
' "${work_items[@]}" | awk 'BEGIN{print "["} {printf "%s%s", sep, $0; sep=","} END{print "]"}' > "$TMP_WORK"
fi

# Hardcoded candidates
hard_items=()
while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  rest=$(echo "$line" | cut -d: -f2- | sed 's/"/\\"/g')
  hard_items+=("{\"file\": \"$file\", \"context\": \"$rest\"}")
done < <(git grep -I --line-number -E "(PASSWORD|API_KEY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|SECRET|TOKEN|PASSWORD=)" -- . 2>/dev/null || true)

if [ ${#hard_items[@]} -gt 0 ]; then
  printf '%s
' "${hard_items[@]}" | awk 'BEGIN{print "["} {printf "%s%s", sep, $0; sep=","} END{print "]"}' > "$TMP_HARD"
fi

# assemble final JSON
GENTS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "{" > "$OUT_FILE"
echo "  \"generated_at\": \"$GENTS\"," >> "$OUT_FILE"
echo -n "  \"repo_secrets\": " >> "$OUT_FILE"
cat "$TMP_REPO" >> "$OUT_FILE"
echo "," >> "$OUT_FILE"
echo -n "  \"workflow_embedded\": " >> "$OUT_FILE"
cat "$TMP_WORK" >> "$OUT_FILE"
echo "," >> "$OUT_FILE"
echo -n "  \"hardcoded_candidates\": " >> "$OUT_FILE"
cat "$TMP_HARD" >> "$OUT_FILE"
echo "" >> "$OUT_FILE"
echo "}" >> "$OUT_FILE"

echo "Wrote inventory to $OUT_FILE"
