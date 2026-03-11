#!/usr/bin/env bash
set -euo pipefail

# CI-free smoke test: runs local health-check in dry-run and validates basic output.
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="artifacts/verify"
OUT_FILE="$OUT_DIR/smoke_check_$TS.txt"

mkdir -p "$OUT_DIR"
echo "Running smoke check (dry-run) at $TS"
echo "Output -> $OUT_FILE"

# Run local health-check in dry-run (no --apply)
./infra/local_secrets_health_check.sh 2>&1 | tee "$OUT_FILE"

# Validate: ensure at least one secret was processed
if grep -q "Processing secret:" "$OUT_FILE"; then
  echo "SMOKE-CHECK: OK - secrets processed"
  exit 0
else
  echo "SMOKE-CHECK: FAIL - no secrets processed"
  # notify_on_failure.sh handles INCIDENT_WEBHOOK or prints summary when unset
  if [ -x "$(dirname "$0")/notify_on_failure.sh" ]; then
    "$(dirname "$0")/notify_on_failure.sh" "FAIL" "$OUT_FILE" || true
  elif [ -x "$(pwd)/scripts/verify/notify_on_failure.sh" ]; then
    "$(pwd)/scripts/verify/notify_on_failure.sh" "FAIL" "$OUT_FILE" || true
  else
    echo "notify_on_failure.sh not found or not executable; skipping notification"
  fi
  exit 2
fi
