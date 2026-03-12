#!/usr/bin/env bash
set -euo pipefail

MANIFEST="k8s/milestone-organizer-cronjob.yaml"
NAMESPACE_OPS=${1:-ops}
MAX_RETRIES=${2:-60}
SLEEP_SEC=${3:-30}

echo "Retrying kubectl apply for $MANIFEST (namespace=$NAMESPACE_OPS)"
for i in $(seq 1 "$MAX_RETRIES"); do
  echo "Attempt $i/$MAX_RETRIES: checking API server..."
  if kubectl version --short >/dev/null 2>&1; then
    echo "API server reachable — applying manifest"
    kubectl apply -f "$MANIFEST" || {
      echo "kubectl apply failed; exiting with non-zero status"
      exit 1
    }
    echo "Apply succeeded"
    exit 0
  else
    echo "API server not reachable yet; sleeping $SLEEP_SEC seconds"
    sleep "$SLEEP_SEC"
  fi
done

echo "Timed out waiting for API server after $MAX_RETRIES attempts"
exit 2
