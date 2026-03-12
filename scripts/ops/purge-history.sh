#!/usr/bin/env bash
set -euo pipefail

# purge-history.sh — guarded helper for repo history purge using git-filter-repo
# Usage: FORCE=1 ./purge-history.sh

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "ERROR: git-filter-repo not found. Install it and retry." >&2
  exit 2
fi

if [ "${FORCE:-0}" != "1" ]; then
  echo "This script is destructive. To run, set FORCE=1 and re-run. Exiting." >&2
  exit 3
fi

TMPDIR=$(mktemp -d)
REPO_URL="git@github.com:kushin77/self-hosted-runner.git"
MIRROR="$TMPDIR/self-hosted-runner.git"
BACKUP_BUNDLE="$PWD/backup-$(date +%Y%m%d%H%M%S).bundle"

echo "Creating mirror clone and backup..."
git clone --mirror "$REPO_URL" "$MIRROR"
pushd "$MIRROR" >/dev/null

# create bundle backup
git bundle create "$BACKUP_BUNDLE" --all

echo "Running git-filter-repo to remove sensitive paths..."

git filter-repo --invert-paths \
  --paths .runner-keys/self-hosted-runner.ed25519 \
  --paths .runner-keys/self-hosted-runner.ed25519.pub \
  --paths build/test_signing_key.pem \
  --paths build/test_ssh_key

# basic verification
echo "Listing recent commits on all branches (truncated)..."
for ref in $(git for-each-ref --format='%(refname)' refs/heads); do
  echo "--- $ref ---"
  git --no-pager log -n 5 --pretty=oneline "$ref" || true
done

read -p "Push cleaned repo to origin (force)? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  git push --force --all
  git push --force --tags
  echo "Pushed cleaned history to origin (force)."
else
  echo "Push aborted. Backup bundle at: $BACKUP_BUNDLE"
fi

popd >/dev/null
rm -rf "$TMPDIR"

echo "Done."
