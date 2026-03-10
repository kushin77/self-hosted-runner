#!/usr/bin/env bash
set -euo pipefail

# Wrapper to run cloud finalization safely and produce a single log+sha256
# Intended to be run by cloud operators with GCP credentials available.

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
log="/tmp/go-live-finalize-${timestamp}.log"

if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "ERROR: GOOGLE_APPLICATION_CREDENTIALS is not set."
  echo "Export: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json"
  exit 2
fi

if [[ ! -r "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
  echo "ERROR: credentials file '${GOOGLE_APPLICATION_CREDENTIALS}' not readable." >&2
  exit 2
fi

echo "Running cloud finalization; log -> ${log}"
bash scripts/go-live-kit/02-deploy-and-finalize.sh |& tee "${log}"

sha="$(sha256sum "${log}" | awk '{print $1}')"
echo "${sha}" > "${log}.sha256"

echo
echo "Cloud finalization complete — log: ${log}"
echo "SHA256: ${sha}"
echo
echo "Please paste the full contents of '${log}' into Issue #2311 (or attach the file)."
echo "If you prefer, copy '${log}.sha256' as the verified hash used by the auto-verifier."

exit 0
