#!/usr/bin/env bash
set -euo pipefail

# Watch /etc/envoy/tls/server.crt for changes and trigger Envoy graceful restart
# by posting to the admin quit endpoint. Kubernetes will restart the pod/container
# if the process exits or fails liveness probe.

CRT=/etc/envoy/tls/server.crt
SLEEP=${SLEEP:-5}

last=""
if [ -f "$CRT" ]; then
  last=$(stat -c %Y "$CRT")
fi

echo "Starting envoy reload watcher (watching $CRT)"
while true; do
  if [ -f "$CRT" ]; then
    now=$(stat -c %Y "$CRT")
    if [ "$now" != "$last" ]; then
      echo "Detected cert change at $(date -u)"
      # Try graceful quit via admin endpoint
      if command -v curl >/dev/null 2>&1; then
        curl -sS -X POST http://127.0.0.1:9901/quitquitquit || true
      else
        echo "curl not available; exiting to allow restart"
        exit 0
      fi
      last=$now
    fi
  fi
  sleep "$SLEEP"
done
