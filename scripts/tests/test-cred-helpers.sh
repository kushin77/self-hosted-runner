#!/usr/bin/env bash
set -euo pipefail

echo "Running credential helper syntax checks..."
BASE_DIR=$(cd "$(dirname "$0")/.." && pwd)
for f in "$BASE_DIR/cred-helpers"/*.sh; do
  echo -n "- Checking $f: "
  if bash -n "$f" 2>/dev/null; then
    echo "OK"
  else
    echo "SYNTAX ERROR"
    exit 1
  fi
done

echo "All credential helper scripts passed syntax check."
