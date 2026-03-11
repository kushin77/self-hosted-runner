#!/usr/bin/env bash
set -euo pipefail
# Usage: run_filter_repo.sh [--dry-run]
# Creates a local mirror at /tmp/repo-mirror.git and runs git-filter-repo

DRY_RUN=1
if [ "${1:-}" = "--apply" ]; then
  DRY_RUN=0
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
MIRROR_DIR=/tmp/repo-mirror.git
REDACT=/home/akushnir/self-hosted-runner/scripts/remediation/redact.txt

echo "Mirror cloning repository to $MIRROR_DIR (mirror)"
rm -rf "$MIRROR_DIR"
git clone --mirror "$REPO_ROOT" "$MIRROR_DIR"

echo "Checking git-filter-repo availability..."
if command -v git-filter-repo >/dev/null 2>&1; then
  GFR_CMD=git-filter-repo
elif python3 -m git_filter_repo --version >/dev/null 2>&1; then
  GFR_CMD="python3 -m git_filter_repo"
else
  echo "git-filter-repo not found. Try: pip install --user git-filter-repo" >&2
  exit 1
fi

cd "$MIRROR_DIR"
echo "Running git-filter-repo with replace-text: $REDACT"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN: Listing potential replacements (no rewrite performed)."
  echo "To perform rewrite: run this script with --apply"
  echo "Previewing files that match patterns..."
  # Use git grep across mirror refs to preview matches
  git --no-pager grep -I -n -E "AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9_]+|-----BEGIN (RSA|OPENSSH|PRIVATE) KEY-----|private_key|client_secret|private_key_id" || true
  echo "Dry-run complete. No history modified." 
else
  echo "APPLY MODE: Rewriting history in local mirror now." 
  $GFR_CMD --replace-text "$REDACT" --force
  echo "Rewrite complete in local mirror at $MIRROR_DIR. Inspect carefully before pushing."
fi

echo "Local mirror location: $MIRROR_DIR"
echo "IMPORTANT: Do NOT push rewritten history until approval and maintenance window."
