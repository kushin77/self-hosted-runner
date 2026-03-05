#!/usr/bin/env bash
set -euo pipefail

# Generate missing `package-lock.json` files and optionally create PRs.
# Usage: ./scripts/gen-lockfiles.sh [--dry-run] [--create-prs]

DRY_RUN=false
CREATE_PRS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --create-prs) CREATE_PRS=true; shift ;;
    -h|--help) echo "Usage: $0 [--dry-run] [--create-prs]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

ROOT_DIR=$(git rev-parse --show-toplevel)
echo "Scanning repo for package.json files under $ROOT_DIR..."

find . -type f -name package.json -not -path "./node_modules/*" -not -path "./.*/node_modules/*" | while read -r pkg; do
  dir=$(dirname "$pkg")
  pushd "$dir" >/dev/null
  if [[ -f package-lock.json || -f yarn.lock ]]; then
    echo "[SKIP] $dir already has a lockfile"
    popd >/dev/null
    continue
  fi

  echo "[GEN] Generating package-lock.json in $dir"
  if $DRY_RUN; then
    echo "  (dry-run) would run: npm install --package-lock-only"
  else
    if command -v npm >/dev/null 2>&1; then
      npm install --package-lock-only --ignore-scripts --no-audit >/dev/null 2>&1 || true
    else
      echo "  npm not found; skipping $dir"
      popd >/dev/null
      continue
    fi

    if [[ -f package-lock.json ]]; then
      echo "  generated package-lock.json in $dir"

      if $CREATE_PRS; then
        branch="add-lockfile-$(echo "$dir" | tr '/ ' '--' | tr -c '[:alnum:]-' '-')-$(date +%Y%m%d)"
        git checkout -b "$branch"
        git add package-lock.json
        git commit -m "chore: add package-lock.json for $dir"
        git push -u origin "$branch"

        if command -v gh >/dev/null 2>&1; then
          gh pr create --title "chore: add package-lock.json for $dir" --body "Automatically generated lockfile for $dir" --base main || true
        else
          echo "  gh CLI not available; created branch $branch and pushed. Create a PR manually."
        fi
      fi
    else
      echo "  failed to generate package-lock.json in $dir"
    fi
  fi

  popd >/dev/null
done

echo "Done."
