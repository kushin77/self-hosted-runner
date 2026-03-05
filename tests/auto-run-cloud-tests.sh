#!/usr/bin/env bash
# Auto-run cloud tests when `tests/cloud-creds.env` is present.
# Intended to be executed on a CI runner or invoked by the web portal after
# credentials are injected. Safe to run locally; will exit if creds missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS_FILE="${SCRIPT_DIR}/cloud-creds.env"
RESULT_LOG="${SCRIPT_DIR}/cloud-tests-auto.log"
ISSUE_FILE="$(cd "$(dirname "${SCRIPT_DIR}")" && pwd)/.github/issues/0013-run-cloud-tests.md"

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

echo "[$(timestamp)] auto-run-cloud-tests started" | tee -a "${RESULT_LOG}"

if [ ! -f "${CREDS_FILE}" ]; then
  echo "[$(timestamp)] No credentials file found at ${CREDS_FILE}; exiting." | tee -a "${RESULT_LOG}"
  # Append note to issue file for audit (non-destructive)
  printf "\n- [%s] Auto-run checked for credentials: none found; waiting for injection.\n" "$(timestamp)" >> "${ISSUE_FILE}"
  exit 0
fi

echo "[$(timestamp)] Found credentials file; preparing environment" | tee -a "${RESULT_LOG}"

# Ensure helper is executable
chmod +x "${SCRIPT_DIR}/prepare-creds.sh" || true
chmod +x "${SCRIPT_DIR}/run-cloud-tests.sh" || true

# Prepare creds (will write secure creds file and set perms)
if ! "${SCRIPT_DIR}/prepare-creds.sh"; then
  echo "[$(timestamp)] prepare-creds.sh failed" | tee -a "${RESULT_LOG}"
  printf "\n- [%s] prepare-creds.sh failed during auto-run.\n" "$(timestamp)" >> "${ISSUE_FILE}"
  exit 2
fi

# Run cloud tests and capture output
echo "[$(timestamp)] Running cloud tests (this may take several minutes)" | tee -a "${RESULT_LOG}"
if "${SCRIPT_DIR}/run-cloud-tests.sh" 2>&1 | tee -a "${RESULT_LOG}"; then
  echo "[$(timestamp)] Cloud tests completed: SUCCESS" | tee -a "${RESULT_LOG}"
  printf "\n- [%s] Cloud tests completed: SUCCESS\n\nClosed: %s\n" "$(timestamp)" "$(date -I)" >> "${ISSUE_FILE}"
  exit 0
else
  rc=${PIPESTATUS[0]:-1}
  echo "[$(timestamp)] Cloud tests completed: FAILURE (rc=${rc})" | tee -a "${RESULT_LOG}"
  printf "\n- [%s] Cloud tests completed: FAILURE (rc=%s). See tests/cloud-test-*.log and %s for details.\n" "$(timestamp)" "${rc}" "${RESULT_LOG}" >> "${ISSUE_FILE}"
  exit ${rc}
fi
