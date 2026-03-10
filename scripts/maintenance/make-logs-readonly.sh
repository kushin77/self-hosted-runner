#!/usr/bin/env bash
set -euo pipefail
# Make log files older than 1 day read-only and record SHA256 checksums
LOGDIR="logs"
CHECKFILE="$LOGDIR/checksums.sha256"
mkdir -p "$LOGDIR"
touch "$CHECKFILE"
find "$LOGDIR" -type f -mtime +0 -print0 | while IFS= read -r -d '' file; do
  chmod 444 "$file" || true
  sha256sum "$file" >> "$CHECKFILE" || true
done
echo "Done: made old logs read-only and updated $CHECKFILE"
