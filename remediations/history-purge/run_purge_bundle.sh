#!/usr/bin/env bash
set -euo pipefail
# Usage: REPO_URL=https://github.com/owner/repo.git DO_PUSH=1 ./run_purge_bundle.sh

WORKDIR="$(pwd)/purge-work"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

GFR_PATH="$WORKDIR/git-filter-repo.py"
if [ ! -f "$GFR_PATH" ]; then
  echo "Downloading git-filter-repo standalone script..."
  curl -fsSL https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo -o "$GFR_PATH"
  chmod +x "$GFR_PATH"
fi

if [ -z "${REPO_URL:-}" ]; then
  echo "ERROR: REPO_URL must be set to the target repository (e.g. https://github.com/owner/repo.git)"
  exit 2
fi

: "${DO_PUSH:=0}"

echo "Mirroring repository..."
rm -rf repo.git
git clone --mirror "$REPO_URL" repo.git
cd repo.git

REPO_ROOT_DIR=$(pwd)
REPLACE_FILE="$WORKDIR/replace.txt"
if [ ! -f "$REPLACE_FILE" ]; then
  echo "ERROR: replace.txt not found at $REPLACE_FILE"
  exit 3
fi

echo "Running git-filter-repo with replace file"
python3 "$GFR_PATH" --replace-text "$REPLACE_FILE"

if [ "$DO_PUSH" = "1" ]; then
  echo "Pushing rewritten history back to origin (force)"
  git push --mirror origin
else
  echo "DO_PUSH!=1; skipping push. Inspect $WORKDIR/repo.git for results. When ready, re-run with DO_PUSH=1."
fi
