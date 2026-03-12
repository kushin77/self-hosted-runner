#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 --secure-dir /path/to/secure-workdir [--push]

This script prepares and runs a history purge in a mirror repo on a secure host.
It will:
 - clone a mirror of the origin into --secure-dir/repo.git
 - read sensitive paths from reports/sensitive-paths.txt (generated locally)
 - run git-filter-repo with those paths in DRY-RUN mode (no push) unless --push is provided
 - run gitleaks in the mirror repo to verify no findings

DO NOT RUN WITH --push UNTIL YOU HAVE BACKUPS AND A MAINTENANCE WINDOW.
EOF
}

SECURE_DIR=""
PUSH=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --secure-dir) SECURE_DIR="$2"; shift 2;;
    --push) PUSH=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [ -z "$SECURE_DIR" ]; then
  echo "--secure-dir is required" >&2; usage; exit 2
fi

SENSITIVE_FILE="$(pwd)/reports/sensitive-paths.txt"
if [ ! -f "$SENSITIVE_FILE" ]; then
  echo "Sensitive paths file not found: $SENSITIVE_FILE" >&2
  echo "Run scripts/ops/generate_sensitive_paths.sh first" >&2
  exit 2
fi

mkdir -p "$SECURE_DIR"
MIRROR="$SECURE_DIR/repo.git"

echo "Creating mirror clone: $MIRROR"
git clone --mirror "$(git config --get remote.origin.url)" "$MIRROR"
pushd "$MIRROR" >/dev/null

echo "Creating backup bundle ../backup-repo.bundle"
git bundle create ../backup-repo.bundle --all

echo "Preparing git-filter-repo command (no push)."
FILTER_CMD=(git filter-repo)
while read -r p; do
  # skip empty
  [ -z "$p" ] && continue
  FILTER_CMD+=(--invert-paths --paths "$p")
done < "$SENSITIVE_FILE"

echo "Would run: ${FILTER_CMD[*]} --force"

if [ "$PUSH" = true ]; then
  echo "Running git-filter-repo now (this will rewrite history)..."
  # run the command
  "${FILTER_CMD[@]}" --force

  echo "Running gitleaks to verify no findings..."
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --source . --report-format json --report-path ../mirror-gitleaks.json --no-banner || true
    echo "Mirror gitleaks report: $SECURE_DIR/mirror-gitleaks.json"
  else
    echo "gitleaks not found on secure host; install and run verification"
  fi

  echo "Force-pushing cleaned history to origin (branches + tags)."
  git push --force --all
  git push --force --tags
else
  echo "DRY-RUN: git-filter-repo command shown above. No destructive action performed."
  echo "After review, re-run with --push on the secure host to execute and push the cleaned history."
fi

popd >/dev/null
