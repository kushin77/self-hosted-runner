#!/usr/bin/env bash

echo "Smoke test for branch: $(git rev-parse --abbrev-ref HEAD)"
if command -v bash >/dev/null 2>&1; then
  echo "bash available"
else
  echo "bash missing" >&2; exit 2
fi
exit 0
