#!/usr/bin/env bash
set -euo pipefail
# Quick syntax check (bash -n) for key scripts we modified as a smoke test.
ROOT_DIR=$(dirname "$0")/..
SCRIPTS=(
  "$ROOT_DIR/scripts/ci/setup-self-hosted-runner.sh"
  "$ROOT_DIR/services/provisioner-worker/deploy/deploy_to_host.sh"
  "$ROOT_DIR/scripts/bin/docker-compose"
)

echo "Running quick syntax checks..."
fail=0
for s in "${SCRIPTS[@]}"; do
  if [ -f "$s" ]; then
    echo "- Checking $s"
    if ! bash -n "$s" 2>/dev/null; then
      echo "  Syntax check FAILED: $s"
      fail=1
    fi
  else
    echo "- Skipping missing $s"
  fi
done

if [ "$fail" -eq 1 ]; then
  echo "One or more scripts failed syntax check" >&2
  exit 2
fi

echo "All syntax checks passed."
