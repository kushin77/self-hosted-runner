#!/usr/bin/env bash
set -euo pipefail
# Idempotent automation to rerun failed workflow runs and enable auto-merge on eligible PRs.
# Designed to be run in CI (GitHub Actions) or manually on a runner with GH CLI configured.

REPO_FULL="${REPO_FULL:-kushin77/self-hosted-runner}"
OWNER="${OWNER:-kushin77}"
REPO="${REPO:-self-hosted-runner}"
TMP_DIR="$(mktemp -d)"
LOG="$TMP_DIR/auto_merge.log"

exec &> >(tee -a "$LOG")

echo "auto_merge_worker start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "repo: $REPO_FULL"

echo "\n1) Collect failed workflow runs (last 250)"
if ! gh run list --repo "$REPO_FULL" --limit 250 --json databaseId,name,conclusion,status,url > "$TMP_DIR/run_list.json"; then
  echo "gh run list failed; ensure GH CLI authenticated and repo exists" >&2
else
  jq -r '.[] | select(.conclusion=="failure") | .databaseId' "$TMP_DIR/run_list.json" > "$TMP_DIR/failed_run_ids.txt" || true
fi

if [ -s "$TMP_DIR/failed_run_ids.txt" ]; then
  echo "Found failed runs:"
  jq -r '.[] | select(.conclusion=="failure") | "- id:\(.databaseId) name:\(.name) url:\(.url)"' "$TMP_DIR/run_list.json" || true
  echo "Requesting reruns (idempotent)"
  while read -r id; do
    echo "request rerun: $id"
    gh run rerun --repo "$REPO_FULL" "$id" || echo "rerun request failed for $id"
  done < "$TMP_DIR/failed_run_ids.txt"
else
  echo "No failed runs found."
fi

echo "\n2) Ensure repository auto-merge is enabled"
ALLOW=$(gh api repos/$OWNER/$REPO --jq ".allow_auto_merge" 2>/dev/null || echo "null")
if [ "$ALLOW" != "true" ]; then
  echo "Attempting to enable allow_auto_merge via API..."
  if gh api repos/$OWNER/$REPO -X PATCH -f allow_auto_merge=true >/dev/null 2>&1; then
    echo "Enabled allow_auto_merge = true"
    ALLOW=true
  else
    echo "Failed to enable allow_auto_merge (insufficient permission). Will create an admin issue if needed."
    ALLOW=$(gh api repos/$OWNER/$REPO --jq ".allow_auto_merge" 2>/dev/null || echo "false")
  fi
fi

if [ "$ALLOW" != "true" ]; then
  ISSUE_TITLE="Admin: Enable repository auto-merge for hands-off operation"
  EXISTS=$(gh issue list --repo "$REPO_FULL" --state open --json number,title --jq ".[] | select(.title==\"$ISSUE_TITLE\") | .number" 2>/dev/null || true)
  if [ -z "$EXISTS" ]; then
    BODY=$'Repository auto-merge is currently disabled and needs admin enablement to complete hands-off operations.\n\nSteps for admin:\n1. Go to repository Settings → Options → Merge button settings.\n2. Enable "Allow auto-merge" (or run the API: PATCH /repos/{owner}/{repo} {"allow_auto_merge": true}).\n3. Optionally, configure branch protection policies to permit auto-merge once checks pass.\n\nPurpose:\nEnabling auto-merge allows automation to set PRs to auto-merge when CI checks pass, completing fully hands-off merges.\n\nPlease enable and comment here when done.'
    gh issue create --repo "$REPO_FULL" --title "$ISSUE_TITLE" --body "$BODY" || true
    echo "Created admin issue requesting enablement (or failed due to perms)."
  else
    echo "Admin issue already open: #$EXISTS"
  fi
fi

echo "\n3) List open PRs and enable auto-merge for eligible ones"
gh pr list --repo "$REPO_FULL" --state open --json number,title,mergeable,mergeState,headRefName > "$TMP_DIR/prs.json" || true
jq -c '.[]' "$TMP_DIR/prs.json" 2>/dev/null || true
jq -r '.[] | select((.mergeable=="MERGEABLE") or (.mergeable==true) or (.mergeState=="CLEAN")) | .number' "$TMP_DIR/prs.json" 2>/dev/null | while read -r num; do
  echo "Attempting auto-merge enable for PR #$num"
  gh api -X PUT repos/$OWNER/$REPO/pulls/$num/auto-merge -f merge_method=merge -f commit_title="Auto-merge by automation" || echo "failed to set auto-merge for #$num"
done || true

echo "\nDone: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Log saved to $LOG"

exit 0
