#!/usr/bin/env bash
set -euo pipefail

# Wrapper to run the milestone organizer in automated, idempotent, hands-off mode.
# - Uses `gh` (requires auth). Attempts to source token from credential helpers.
# - Writes append-only audit artifacts to `artifacts/milestones-assignments/`.

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "kushin77/self-hosted-runner")"
ARTIFACT_DIR="artifacts/milestones-assignments"
mkdir -p "$ARTIFACT_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
OPEN_JSON="$ARTIFACT_DIR/open_$TS.json"
CLOSED_JSON="$ARTIFACT_DIR/closed_$TS.json"
AUDIT_LOG="$ARTIFACT_DIR/assignments_$TS.jsonl"

echo "Repo: $REPO"
echo "Artifact dir: $ARTIFACT_DIR"

# Ensure gh auth available; try helper fallbacks (GSM/Vault/KMS helpers should set GH_TOKEN)
if gh auth status >/dev/null 2>&1; then
  echo "gh: authenticated"
else
  echo "gh: not authenticated — attempting credential helpers"
  if [ -x scripts/utilities/credcache.sh ]; then
    echo "Attempting scripts/utilities/credcache.sh get gh_token"
    GH_TOKEN=$(scripts/utilities/credcache.sh get gh_token 2>/dev/null || true)
    if [ -n "${GH_TOKEN:-}" ]; then
      echo "Using GH_TOKEN from credcache"
      echo "$GH_TOKEN" | gh auth login --with-token || true
    fi
  fi
fi

echo "Running organizer (apply) — idempotent"
scripts/utilities/organize_milestones.sh --apply || echo "organizer exited with non-zero status"

echo "Exporting current issue state to artifacts"
gh issue list --state open --limit 1000 --json number,title,milestone > "$OPEN_JSON" || true
gh issue list --state closed --limit 1000 --json number,title,milestone > "$CLOSED_JSON" || true

# Build append-only JSONL audit: one JSON object per line
jq -c '.[] | {state: "open", number: .number, title: .title, milestone: (.milestone|.title // null)}' "$OPEN_JSON" > "$AUDIT_LOG" || true
jq -c '.[] | {state: "closed", number: .number, title: .title, milestone: (.milestone|.title // null)}' "$CLOSED_JSON" >> "$AUDIT_LOG" || true

echo "Wrote audit log: $AUDIT_LOG"
echo "Done"
