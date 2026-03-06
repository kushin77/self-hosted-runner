#!/usr/bin/env bash
set -euo pipefail

# Creates a reproducible archive of the repository for offsite backup.
# Default: creates artifacts/backups/repo-backup-<ts>.tar.gz

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
OUT_DIR="${REPO_ROOT}/artifacts/backups"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="${OUT_DIR}/repo-backup-${TS}.tar.gz"

mkdir -p "$OUT_DIR"

echo "Creating repository archive -> $OUT_FILE"

# Use git archive if available to avoid including ignored files
if command -v git &> /dev/null && [[ -d "$REPO_ROOT/.git" ]]; then
  (cd "$REPO_ROOT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1) || true
  # export HEAD tree
  (cd "$REPO_ROOT" && git archive --format=tar --prefix=repo/ HEAD) | gzip -9 > "$OUT_FILE"
else
  # Fall back to tar excluding large directories
  tar --exclude='./artifacts/backups' --exclude='./node_modules' --exclude='./build' -czf "$OUT_FILE" -C "$REPO_ROOT" .
fi

echo "Archive created: $OUT_FILE"

ls -lh "$OUT_FILE"

echo "Backup complete"
