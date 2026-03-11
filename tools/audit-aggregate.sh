#!/usr/bin/env bash

# Merge all secret-mirror JSONL audit files into a single aggregate and optionally sign
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_DIR="$REPO_ROOT/logs/secret-mirror"
TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
OUTFILE="$AUDIT_DIR/aggregate-${TIMESTAMP}.jsonl"

mkdir -p "$AUDIT_DIR"

# Find mirror-*.jsonl files, sort by name (versioned timestamps), and concatenate
shopt -s nullglob
files=("$AUDIT_DIR"/mirror-*.jsonl)
if [ ${#files[@]} -eq 0 ]; then
  echo "No mirror audit files found in $AUDIT_DIR"
  exit 0
fi

# Use sort -V on filenames for natural order
printf "%s\n" "${files[@]}" | sort -V | xargs -r cat > "$OUTFILE"

# Optionally sign using GPG if GPG_KEY is set
if command -v gpg >/dev/null 2>&1 && [ -n "${GPG_KEY:-}" ]; then
  echo "Signing $OUTFILE with key $GPG_KEY"
  gpg --batch --yes --local-user "$GPG_KEY" --output "${OUTFILE}.sig" --armor --detach-sign "$OUTFILE"
  echo "Signature written to ${OUTFILE}.sig"
fi

echo "Wrote aggregate audit: $OUTFILE"
exit 0
