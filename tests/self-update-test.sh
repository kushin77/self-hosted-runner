#!/bin/sh
set -eu

echo "Running self-update smoke tests"

if [ ! -f "self-update/check-updates.sh" ]; then
  echo "check-updates.sh missing" >&2
  exit 2
fi

if [ ! -f "self-update/apply-update.sh" ]; then
  echo "apply-update.sh missing" >&2
  exit 2
fi

sh self-update/check-updates.sh --current self-update/version --remote-version 0.1.1 || rc=$?; true
if [ "${rc:-0}" -ne 10 ]; then
  echo "expected update-available exit code 10 when remote > current, got $rc" >&2
  exit 3
fi

sh self-update/apply-update.sh --current self-update/version --artifact-url https://example.com/art.tar.gz --dry-run

echo "self-update smoke tests passed"
exit 0
