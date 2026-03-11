#!/usr/bin/env bash
set -euo pipefail

# verify_deployment.sh
# Run on the hardened runner to collect verification evidence for sign-off.
# Usage: S3_BUCKET=chaos-forensic-logs ./scripts/ops/verify_deployment.sh

S3_BUCKET="${S3_BUCKET:-}"
# allow first arg as bucket
if [ -n "${1:-}" ] && [ -z "${S3_BUCKET// /}" ]; then
  S3_BUCKET="$1"
fi

LOG_DIR="/var/log/chaos"
REPO_DIR="/opt/runner/repo"
OUT="/tmp/deployment_verification_$(date -u +%Y%m%dT%H%M%SZ).txt"

echo "Deployment verification started at $(date -u)" | tee "$OUT"

printf '\n=== Crontab (runner) ===\n' | tee -a "$OUT"
sudo crontab -u runner -l 2>&1 | tee -a "$OUT" || echo "(no crontab found)" | tee -a "$OUT"

printf '\n=== Orchestrator log (tail 200) ===\n' | tee -a "$OUT"
if ls "$LOG_DIR"/orchestrator-*.log 1> /dev/null 2>&1; then
  latest=$(ls -1t "$LOG_DIR"/orchestrator-*.log | head -n1)
  echo "Latest orchestrator log: $latest" | tee -a "$OUT"
  echo "----" | tee -a "$OUT"
  tail -n 200 "$latest" | tee -a "$OUT"
else
  echo "No orchestrator logs found in $LOG_DIR" | tee -a "$OUT"
fi

printf '\n=== Uploader log (tail 200) ===\n' | tee -a "$OUT"
if ls "$LOG_DIR"/uploader-*.log 1> /dev/null 2>&1; then
  latestu=$(ls -1t "$LOG_DIR"/uploader-*.log | head -n1)
  echo "Latest uploader log: $latestu" | tee -a "$OUT"
  echo "----" | tee -a "$OUT"
  tail -n 200 "$latestu" | tee -a "$OUT"
else
  echo "No uploader logs found in $LOG_DIR" | tee -a "$OUT"
fi

printf '\n=== Local JSONL reports (sample) ===\n' | tee -a "$OUT"
if [ -d "$REPO_DIR/reports/chaos" ]; then
  ls -lah "$REPO_DIR/reports/chaos" | tee -a "$OUT"
  sample=$(ls -1t "$REPO_DIR/reports/chaos"/*.jsonl 2>/dev/null | head -n1 || true)
  if [ -n "$sample" ]; then
    echo "---- sample: $sample" | tee -a "$OUT"
    head -n 200 "$sample" | tee -a "$OUT"
  else
    echo "No .jsonl files found in $REPO_DIR/reports/chaos" | tee -a "$OUT"
  fi
else
  echo "No reports/chaos directory found under $REPO_DIR" | tee -a "$OUT"
fi

if [ -n "${S3_BUCKET// /}" ]; then
  printf '\n=== S3 verification for bucket: %s ===\n' "$S3_BUCKET" | tee -a "$OUT"
  # Fetch credentials at runtime
  if [ -f "$REPO_DIR/scripts/ops/fetch_credentials.sh" ]; then
    echo "Fetching credentials via fetch_credentials.sh" | tee -a "$OUT"
    # shellcheck source=/dev/null
    source "$REPO_DIR/scripts/ops/fetch_credentials.sh" 2>>"$OUT" || echo "Credential fetch failed" | tee -a "$OUT"
  else
    echo "fetch_credentials.sh not found; skipping credential fetch" | tee -a "$OUT"
  fi

  echo "-- bucket versioning --" | tee -a "$OUT"
  aws s3api get-bucket-versioning --bucket "$S3_BUCKET" 2>&1 | tee -a "$OUT" || echo "(error querying versioning)" | tee -a "$OUT"
  echo "-- object lock config --" | tee -a "$OUT"
  aws s3api get-object-lock-configuration --bucket "$S3_BUCKET" 2>&1 | tee -a "$OUT" || echo "(error querying object-lock)" | tee -a "$OUT"
  echo "-- list chaos logs --" | tee -a "$OUT"
  aws s3 ls "s3://$S3_BUCKET/chaos-logs/" --recursive | head -n 50 | tee -a "$OUT" || echo "(error listing bucket)" | tee -a "$OUT"
else
  printf '\nS3_BUCKET not provided; skipping S3 checks\n' | tee -a "$OUT"
fi

# Summarize
printf '\n=== Summary ===\n' | tee -a "$OUT"
echo "Generated evidence file: $OUT" | tee -a "$OUT"

# Optional: if ONPREM_HOST is provided, attempt to SSH and run remote verifier
ONPREM_HOST="${ONPREM_HOST:-}"
ONPREM_USER="${ONPREM_USER:-runner}"
if [ -n "$ONPREM_HOST" ]; then
  printf '\n=== Remote verification on %s ===\n' "$ONPREM_HOST" | tee -a "$OUT"
  # Ensure fetch_credentials is available to provide SSH_KEY_PATH
  if [ -f "$REPO_DIR/scripts/ops/fetch_credentials.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO_DIR/scripts/ops/fetch_credentials.sh" 2>>"$OUT" || echo "Credential fetch (for SSH) failed" | tee -a "$OUT"
  fi

  if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "$SSH_KEY_PATH" ]; then
    echo "Using SSH key at $SSH_KEY_PATH to connect to $ONPREM_HOST" | tee -a "$OUT"
    REMOTE_CMD="sudo /opt/runner/repo/scripts/ops/verify_deployment.sh ${S3_BUCKET:-} || true"
    echo "Running remote verifier..." | tee -a "$OUT"
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$ONPREM_USER@$ONPREM_HOST" "$REMOTE_CMD" 2>&1 | tee -a "$OUT" || echo "Remote command failed or unreachable" | tee -a "$OUT"
  else
    echo "SSH key not available; cannot run remote verifier on $ONPREM_HOST" | tee -a "$OUT"
  fi
fi

printf '\nPlease paste the contents of %s into the stakeholder sign-off issue (#2594) as verification evidence.\n' "$OUT" | tee -a "$OUT"

echo "Deployment verification complete at $(date -u)" | tee -a "$OUT"

exit 0
