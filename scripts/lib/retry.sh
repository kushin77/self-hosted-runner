#!/bin/bash
# retry.sh - simple retry with exponential backoff + jitter
# Usage: retry_cmd <max_attempts> <base_delay_seconds> -- cmd args...

# Allow optional per-run overrides via ../config/retry_override.sh
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERRIDE_FILE="$LIB_DIR/../config/retry_override.sh"
if [ -f "$OVERRIDE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$OVERRIDE_FILE"
fi

retry_cmd() {
  local max_attempts=${1:-3}
  local base_delay=${2:-1}
  shift 2
  local attempt=1
  local exit_code=0
  while true; do
    if "$@"; then
      return 0
    else
      exit_code=$?
      if [ $attempt -ge $max_attempts ]; then
        return $exit_code
      fi
      # exponential backoff with jitter
      local sleep_time
      sleep_time=$(awk -v b="$base_delay" -v a="$attempt" 'BEGIN{s=b*(2^(a-1)); srand(); print s*(0.5+rand())}')
      sleep $(printf "%.0f" "$sleep_time")
      attempt=$((attempt+1))
    fi
  done
}

export -f retry_cmd
