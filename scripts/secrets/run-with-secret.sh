#!/usr/bin/env bash
set -euo pipefail

# run-with-secret.sh
# Wrapper to run a command with a secret fetched via the helper.
# By default the secret is provided on FD 3 (preferred). Optionally set --env
# to inject the secret into an environment variable `SECRET_VALUE` (less
# secure; environment variables may be visible to other processes).
#
# Usage:
#  # FD-based (preferred):
#  GSM_PROJECT=... GSM_SECRET_NAME=... ./run-with-secret.sh -- my-service --serve
#
#  # Env-based (careful):
#  GSM_PROJECT=... GSM_SECRET_NAME=... ./run-with-secret.sh --env -- my-service --serve

mode_env=false

if [ "${1:-}" = "--env" ]; then
  mode_env=true
  shift
fi

if [ "${1:-}" != "--" ]; then
  echo "Usage: [--env] -- command..." >&2
  exit 2
fi
shift

if [ $# -eq 0 ]; then
  echo "No command provided" >&2
  exit 2
fi

cmd=("$@")

# Ensure helper exists
helper="$(dirname "$0")/fetch-secret-oidc-gsm-vault.sh"
if [ ! -x "$helper" ]; then
  echo "Missing helper: $helper" >&2
  exit 2
fi

tmp=$(mktemp)
chmod 600 "$tmp"
trap 'shred -u "$tmp" 2>/dev/null || rm -f "$tmp"' EXIT

# Fetch secret into temp file
if ! "$helper" > "$tmp"; then
  echo "Secret fetch failed" >&2
  exit 1
fi

if [ "$mode_env" = true ]; then
  # Less secure: inject into environment variable
  SECRET_VALUE=$(cat "$tmp")
  unset tmp
  exec env SECRET_VALUE="$SECRET_VALUE" "${cmd[@]}"
else
  # Preferred: provide secret on file descriptor 3 and set SECRET_FD=3
  exec env SECRET_FD=3 "${cmd[@]}" 3<"$tmp"
fi
