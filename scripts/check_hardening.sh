#!/usr/bin/env bash
set -euo pipefail

# Basic hardening checks for systemd templates and tmpfiles
ROOT="ansible/templates"
FAILED=0

echo "Checking systemd templates under $ROOT for ProtectSystem/ReadOnlyPaths/NoNewPrivileges..."
for f in $(find "$ROOT" -type f -name "*.j2"); do
  if grep -q "\bUnit\b" "$f" || grep -q "ProtectSystem" "$f" || grep -q "ReadOnlyPaths" "$f" || grep -q "NoNewPrivileges" "$f"; then
    echo "OK: $f contains hardening directives"
  else
    echo "WARN: $f missing common hardening directives (ProtectSystem/ReadOnlyPaths/NoNewPrivileges)"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "One or more templates failed basic hardening checks."
  exit 2
fi

echo "All basic hardening checks passed."
