#!/usr/bin/env bash
set -euo pipefail
# auto_rotate_runners.sh: iterate a list of runners and call rotate-runner.sh
# Config format (one per line, CSV): <runner_dir>,<repo_url>,<runner_name>,<vault_secret_path>
# Lines starting with # are ignored.

CONFIG=${1:-/etc/actions-runner/rotation.conf}
DRY=${DRY:-}
VAULT_ADDR=${VAULT_ADDR:-}

if [ ! -f "$CONFIG" ]; then
  echo "Config file $CONFIG not found" >&2
  exit 2
fi

while IFS= read -r line; do
  line=$(echo "$line" | sed 's/^\s*//;s/\s*$//')
  [ -z "$line" ] && continue
  case "$line" in
    \#*) continue ;;
  esac
  IFS=',' read -r runner_dir repo_url runner_name secret_path <<<"$line"
  runner_dir=$(echo "$runner_dir" | xargs)
  repo_url=$(echo "$repo_url" | xargs)
  runner_name=$(echo "$runner_name" | xargs)
  secret_path=$(echo "$secret_path" | xargs)

  echo "Rotating runner $runner_name at $runner_dir (secret: $secret_path)"
  if [ -n "${DRY}" ]; then
    DRY=1 VAULT_ADDR="$VAULT_ADDR" ./scripts/ci/rotate-runner.sh "$runner_dir" "$repo_url" "$runner_name" "$secret_path" || true
  else
    VAULT_ADDR="$VAULT_ADDR" ./scripts/ci/rotate-runner.sh "$runner_dir" "$repo_url" "$runner_name" "$secret_path" || echo "Rotation failed for $runner_name" >&2
  fi

done < "$CONFIG"
