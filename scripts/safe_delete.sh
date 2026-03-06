#!/usr/bin/env bash
set -euo pipefail

# safe_delete.sh - Guarded wrapper around dangerous deletes
# Usage: safe_delete.sh --path /some/path [--confirm] [--dry-run]

DRY_RUN=true
CONFIRM=false
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      TARGET="$2"; shift 2;;
    --confirm)
      CONFIRM=true; shift;;
    --dry-run)
      DRY_RUN=true; shift;;
    --no-dry-run)
      DRY_RUN=false; shift;;
    -h|--help)
      echo "Usage: $0 --path <path> [--confirm] [--dry-run|--no-dry-run]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Error: --path is required" >&2
  exit 2
fi

if [ "$CONFIRM" != true ]; then
  echo "Refusing to delete $TARGET without --confirm flag. Use --dry-run to preview." >&2
  exit 3
fi

if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] Would delete: $TARGET"
  exit 0
fi

echo "Deleting $TARGET ..."
sudo rm -rf -- "$TARGET"
echo "Delete completed."
