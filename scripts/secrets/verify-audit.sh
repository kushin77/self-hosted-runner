#!/usr/bin/env bash

# Verify an aggregated audit bundle and optional GPG signature
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <aggregate.jsonl>"
  exit 2
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "File not found: $FILE"
  exit 2
fi

if [ -f "${FILE}.sig" ]; then
  if command -v gpg >/dev/null 2>&1; then
    echo "Verifying GPG signature ${FILE}.sig..."
    if gpg --verify "${FILE}.sig" "$FILE" 2>/dev/null; then
      echo "Signature verified"
      exit 0
    else
      echo "Signature verification failed" >&2
      exit 3
    fi
  else
    echo "gpg not installed; cannot verify signature" >&2
    exit 4
  fi
else
  echo "No signature found for $FILE; performing JSONL format check"
  if command -v jq >/dev/null 2>&1; then
    # Validate each line is valid JSON
    local_bad=0
    while IFS= read -r line; do
      if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
        echo "Invalid JSON line detected: $line" >&2
        local_bad=1
        break
      fi
    done < "$FILE"
    if [ "$local_bad" -eq 0 ]; then
      echo "JSONL format OK"
      exit 0
    else
      exit 5
    fi
  else
    echo "jq not available; cannot validate JSONL contents" >&2
    exit 6
  fi
fi
