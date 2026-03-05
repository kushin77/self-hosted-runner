#!/bin/sh
# Basic health-check for runner after update. Return 0 on success.
set -eu

# If HEALTHCHECK_CMD is set, run it and use its exit status.
if [ -n "${HEALTHCHECK_CMD:-}" ]; then
  sh -c "$HEALTHCHECK_CMD"
  exit $?
fi

# Default: if systemd is available, check runner.service is active.
if [ -f /proc/1/comm ] && grep -q systemd /proc/1/comm 2>/dev/null && command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet runner.service; then
    echo "runner.service is active"
    exit 0
  else
    echo "runner.service is not active" >&2
    exit 2
  fi
else
  # No systemd; attempt a lightweight check: presence of current directory and a PID file.
  if [ -f "/home/akushnir/self-hosted-runner/current/DEPLOYED_FROM" ]; then
    echo "current release present"
    exit 0
  else
    echo "no clear health indicator available" >&2
    exit 3
  fi
fi
