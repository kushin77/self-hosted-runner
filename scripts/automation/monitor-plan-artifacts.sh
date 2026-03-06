#!/usr/bin/env bash
set -euo pipefail

# Monitors GitHub Actions workflow runs for `terraform-plan-apply.yml`,
# downloads plan artifacts when available, commits them to the repo, and
# notifies Issue #246 for plan review.

REPO="kushin77/self-hosted-runner"
WORKFLOW_FILE="terraform-plan-apply.yml"
POLL_INTERVAL=${1:-30}
DEST_DIR="$(pwd)/artifacts/plans"
LAST_FILE="/tmp/plan-monitor-last-id"
LOG="/tmp/plan-monitor.log"

mkdir -p "$DEST_DIR"
touch "$LOG"

echo "Monitor started at $(date -u)" >> "$LOG"

last_seen=0
if [ -f "$LAST_FILE" ]; then
  last_seen=$(cat "$LAST_FILE" || echo 0)
fi

while true; do
  echo "Checking workflow runs at $(date -u)" >> "$LOG"
  # List recent runs for the workflow
  runs_json=$(gh api repos/$REPO/actions/workflows/$WORKFLOW_FILE/runs --jq '.workflow_runs') || {
    echo "gh api failed — sleeping" >> "$LOG"
    sleep "$POLL_INTERVAL"
    continue
  }

  # Iterate runs (newest first)
  echo "$runs_json" | jq -c '.[]' | while read -r run; do
    run_id=$(echo "$run" | jq -r '.id')
    status=$(echo "$run" | jq -r '.status')
    conclusion=$(echo "$run" | jq -r '.conclusion')

    if [ "$run_id" -le "$last_seen" ]; then
      continue
    fi

    # Only act on completed runs
    if [ "$status" = "completed" ]; then
      echo "Found completed run $run_id (conclusion=$conclusion)" >> "$LOG"

      # Download artifacts
      TMPDIR=$(mktemp -d)
      echo "Downloading artifacts for run $run_id into $TMPDIR" >> "$LOG"
      gh run download "$run_id" --repo "$REPO" -D "$TMPDIR" >> "$LOG" 2>&1 || true

      # Look for JSON plan files
      found=0
      for f in $(find "$TMPDIR" -type f -name '*.json' -o -name '*plan*.json' 2>/dev/null); do
        base=$(basename "$f")
        dest="$DEST_DIR/plan-run-${run_id}-${base}"
        mv "$f" "$dest" || cp "$f" "$dest" || true
        git -C "$(pwd)" add "$dest" || true
        found=1
        echo "Saved plan artifact to $dest" >> "$LOG"
      done

      if [ $found -eq 1 ]; then
        git -C "$(pwd)" commit -m "chore: import plan artifact from workflow run $run_id" --no-verify || true
        git -C "$(pwd)" push origin HEAD || true

        gh issue comment 246 --body "Imported plan artifact from workflow run $run_id: artifacts/plans/ (see committed files). Please review and approve to schedule Apply." >> "$LOG" 2>&1 || true
      else
        echo "No plan JSON artifacts found in run $run_id" >> "$LOG"
      fi

      # Use safe_delete wrapper to remove temp download dir
      SAFE_DELETE="$(pwd)/scripts/safe_delete.sh"
      if [ ! -x "$SAFE_DELETE" ]; then SAFE_DELETE="$(dirname "$0")/../../scripts/safe_delete.sh"; fi
      if [ -x "$SAFE_DELETE" ]; then
        "$SAFE_DELETE" --path "$TMPDIR" --dry-run || true
      else
        rm -rf "$TMPDIR"
      fi
      echo "$run_id" > "$LAST_FILE"
      last_seen=$run_id
    fi
  done

  sleep "$POLL_INTERVAL"
done
