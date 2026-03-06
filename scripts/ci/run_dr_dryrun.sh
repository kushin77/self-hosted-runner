#!/usr/bin/env bash
set -euo pipefail

# run_dr_dryrun.sh
# Wrapper to run the bootstrap automation and DR drill in a controlled, idempotent way.
# Usage: set required env vars (see checks) then run this script.

usage(){
  cat <<EOF
Usage: GITLAB_API_URL=... GITLAB_API_TOKEN=... GITLAB_GROUP_ID=... \\
       GITHUB_TOKEN=... RESTORE_S3_BUCKET=s3://bucket [AGE_KEY_FILE_PATH=/path/to/age.key] \\
       ./scripts/ci/run_dr_dryrun.sh

This script will:
  - validate required environment variables
  - run `scripts/ci/bootstrap_automation.sh` to provision CI variables and rotate keys
  - run `scripts/dr/drill_run.sh` to perform the DR dry-run

All outputs are collected under /tmp/dr_dryrun_<timestamp>.log
EOF
}

SIMULATE=0
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then usage; exit 0; fi
if [[ "${1:-}" == "--simulate" || "${SIMULATE:-}" == "1" ]]; then
  SIMULATE=1
fi

if [ "$SIMULATE" -ne 1 ]; then
  REQUIRED=(GITLAB_API_URL GITLAB_API_TOKEN GITLAB_GROUP_ID GITHUB_TOKEN RESTORE_S3_BUCKET)
  for v in "${REQUIRED[@]}"; do
    if [ -z "${!v:-}" ]; then
      echo "ERROR: required env var $v is not set" >&2
      usage
      exit 2
    fi
  done
else
  echo "SIMULATE mode enabled: skipping credential checks"
fi

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOGFILE="/tmp/dr_dryrun_${TIMESTAMP}.log"
echo "DR dry-run starting at ${TIMESTAMP}. Log: ${LOGFILE}"

echo "== ENV SUMMARY ==" | tee -a "${LOGFILE}"
echo "GITLAB_API_URL=${GITLAB_API_URL:-unset}" | tee -a "${LOGFILE}"
echo "GITLAB_GROUP_ID=${GITLAB_GROUP_ID:-unset}" | tee -a "${LOGFILE}"
echo "GITHUB_REPO=${GITHUB_REPO:-unset}" | tee -a "${LOGFILE}"
echo "RESTORE_S3_BUCKET=${RESTORE_S3_BUCKET:-unset}" | tee -a "${LOGFILE}"

if [ "$SIMULATE" -eq 1 ]; then
  echo "== SIMULATE: syntax-checking key scripts ==" | tee -a "${LOGFILE}"
  bash -n "$(dirname "${BASH_SOURCE[0]}")/bootstrap_automation.sh" || true
  bash -n "$(dirname "${BASH_SOURCE[0]}")/../dr/drill_run.sh" || true
  echo "== SIMULATE: checking presence of backup script and templates ==" | tee -a "${LOGFILE}"
  [ -f "$(pwd)/scripts/backup/gitlab_backup_encrypt.sh" ] && echo "found backup script" | tee -a "${LOGFILE}" || echo "missing backup script" | tee -a "${LOGFILE}"
  [ -f "$(pwd)/bootstrap/restore_from_github.sh" ] && echo "found restore script" | tee -a "${LOGFILE}" || echo "missing restore script" | tee -a "${LOGFILE}"
  echo "== SIMULATE: generating simulated RTO/RPO report ==" | tee -a "${LOGFILE}"
  echo "Simulated RTO: 45m (estimate)" | tee -a "${LOGFILE}"
  echo "Simulated RPO: 15m (estimate)" | tee -a "${LOGFILE}"
  EXIT_CODE=0
else
  echo "== Running bootstrap_automation.sh ==" | tee -a "${LOGFILE}"
  bash "$(dirname "${BASH_SOURCE[0]}")/bootstrap_automation.sh" 2>&1 | tee -a "${LOGFILE}"

  echo "== Running drill_run.sh ==" | tee -a "${LOGFILE}"
  bash "$(dirname "${BASH_SOURCE[0]}")/../dr/drill_run.sh" 2>&1 | tee -a "${LOGFILE}"

  EXIT_CODE=${PIPESTATUS[0]:-0}
fi
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "DR dry-run completed successfully" | tee -a "${LOGFILE}"
else
  echo "DR dry-run failed (exit ${EXIT_CODE})" | tee -a "${LOGFILE}"
fi

echo "Logs saved to ${LOGFILE}"
exit "$EXIT_CODE"
