#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Local multi-layer secrets health check (GSM, Vault, KMS)
# Usage: run locally in an operator environment with appropriate cloud CLIs configured.

OUT=/tmp/local_secrets_health_report.json
echo '{' > "$OUT"

echo "Starting local secrets health check..."

check_cmd() {
  local name=$1; shift
  local cmd=$*
  echo "- Checking $name..."
  local i=0
  local max=3
  local wait=2
  while [ $i -lt $max ]; do
    if eval "$cmd" >/tmp/.check_${name} 2>&1; then
      echo "{\"$name\": {\"status\": \"ok\"}}" >> "$OUT" 2>/dev/null || true
      return 0
    fi
    i=$((i+1))
    sleep $wait
    wait=$((wait * 2))
  done
  echo "{\"$name\": {\"status\": \"fail\", \"log\": \"$(sed -n '1,400p' /tmp/.check_${name} | sed 's/"/\\"/g')\"}}" >> "$OUT" 2>/dev/null || true
  return 1
}

summary_started=false
append_comma_if_needed() {
  if [ "$summary_started" = true ]; then
    sed -i '$ s/$/,/' "$OUT"
  fi
  summary_started=true
}

append_comma_if_needed
echo '"layer_gsm":' >> "$OUT"
{
  if command -v gcloud >/dev/null 2>&1; then
    if check_cmd gsm "gcloud auth application-default print-access-token >/dev/null"; then
      echo "  "
    fi
  else
    echo "{\"gsm\": {\"status\": \"skipped\", \"reason\": \"gcloud not installed\"}}" >> "$OUT"
  fi
} || true

append_comma_if_needed
echo '"layer_vault":' >> "$OUT"
{
  if [ -n "${VAULT_ADDR:-}" ]; then
    check_cmd vault "curl -sSf --connect-timeout 5 \"${VAULT_ADDR%/}/v1/sys/health\" | (command -v jq >/dev/null 2>&1 && jq .) || cat -" || true
  else
    echo "{\"vault\": {\"status\": \"skipped\", \"reason\": \"VAULT_ADDR not set\"}}" >> "$OUT"
  fi
} || true

append_comma_if_needed
echo '"layer_kms":' >> "$OUT"
{
  if command -v aws >/dev/null 2>&1; then
    if [ -n "${AWS_KMS_KEY_ID:-}" ]; then
      check_cmd kms "aws sts get-caller-identity --output json >/dev/null && aws kms describe-key --key-id \"$AWS_KMS_KEY_ID\" --output json >/dev/null"
    else
      echo "{\"kms\": {\"status\": \"skipped\", \"reason\": \"AWS_KMS_KEY_ID not set\"}}" >> "$OUT"
    fi
  else
    echo "{\"kms\": {\"status\": \"skipped\", \"reason\": \"aws cli not installed\"}}" >> "$OUT"
  fi
} || true

# Close JSON report
sed -i -e '$ s/,$//' "$OUT" || true
echo '}' >> "$OUT"

echo "Local health report written to $OUT"
cat "$OUT"

exit 0
