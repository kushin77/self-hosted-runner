#!/usr/bin/env bash
# check_ssh_and_retry.sh
# Tries to SSH to a host using the deploy key with retries and exponential backoff.

set -euo pipefail

TARGET_HOST="${TARGET_HOST:-staging.example.com}"
TARGET_USER="${TARGET_USER:-deploy}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/deploy_key}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-6}"
INITIAL_SLEEP="${INITIAL_SLEEP:-5}"

attempt=1
sleep_time=$INITIAL_SLEEP

echo "Checking SSH connectivity to ${TARGET_USER}@${TARGET_HOST} using key ${KEY_PATH} (max ${MAX_ATTEMPTS} attempts)"

while [ $attempt -le $MAX_ATTEMPTS ]; do
  echo "Attempt ${attempt}/${MAX_ATTEMPTS}: ssh -o BatchMode=yes -o ConnectTimeout=5 -i ${KEY_PATH} ${TARGET_USER}@${TARGET_HOST} 'echo connected'"
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "${KEY_PATH}" "${TARGET_USER}@${TARGET_HOST}" 'echo connected' >/dev/null 2>&1; then
    echo "SSH connectivity verified on attempt ${attempt}"
    exit 0
  fi

  echo "SSH not ready (attempt ${attempt}). Sleeping ${sleep_time}s before retry..."
  sleep ${sleep_time}
  attempt=$((attempt+1))
  sleep_time=$((sleep_time*2))
done

echo "SSH connectivity could not be established after ${MAX_ATTEMPTS} attempts."
exit 2
