#!/usr/bin/env bash
set -euo pipefail

echo "[integration-tests] Starting static checks for rotation scripts"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Checking syntax for all shell scripts under scripts/rotation/"
ret=0
for f in "$ROOT_DIR"/rotation/*.sh; do
  [ -e "$f" ] || continue
  echo " - bash -n $f"
  if ! bash -n "$f"; then
    echo "[ERROR] Syntax error in $f"
    ret=2
  fi
done

echo "Scanning for potential secret exposures in scripts/ and audit/"
grep -R --line-number -E "(AWS_SECRET|AWS_SECRET_ACCESS_KEY|VAULT_TOKEN|GCP_SERVICE_ACCOUNT|PRIVATE_KEY|BEGIN RSA PRIVATE KEY)" "$ROOT_DIR" || true

echo "Searching for network and destructive commands in rotation scripts (report only)"
grep -R --line-number -E "\b(curl|wget|aws |gcloud |vault |kubectl |rm -rf|scp )\b" "$ROOT_DIR"/rotation || true

echo "Idempotency smoke: ensure scripts are safe to run multiple times (manual verification recommended)"
echo "Integration tests completed (static checks only). Review output and attach logs."
exit $ret
