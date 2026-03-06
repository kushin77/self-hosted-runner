#!/usr/bin/env bash
set -euo pipefail

# validate_runner_readiness.sh
# Check kubernetes connectivity and gitlab-runner pod readiness in `gitlab-runner` namespace.
# Usage: KUBECONFIG=/path/to/kubeconfig ./scripts/ci/validate_runner_readiness.sh

if [ -z "${KUBECONFIG:-}" ]; then
  echo "KUBECONFIG not set. Export KUBECONFIG or pass kubeconfig via env." >&2
  exit 2
fi

NAMESPACE=${1:-gitlab-runner}
TIMEOUT=${2:-60}

export KUBECONFIG

echo "Checking cluster connectivity..."
if ! kubectl version --request-timeout=5s >/dev/null 2>&1; then
  echo "ERROR: Unable to contact API server from KUBECONFIG=${KUBECONFIG}" >&2
  exit 2
fi

echo "Ensuring namespace ${NAMESPACE} exists..."
if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
  echo "ERROR: Namespace ${NAMESPACE} not found" >&2
  exit 2
fi

echo "Checking gitlab-runner pods readiness (timeout ${TIMEOUT}s)..."
end=$((SECONDS + TIMEOUT))
while [ ${SECONDS} -lt ${end} ]; do
  pod_info=$(kubectl -n "${NAMESPACE}" get pods -l app=gitlab-runner -o jsonpath='{range .items[*]}{.metadata.name}: {.status.phase} {.status.containerStatuses[*].ready}\n{end}' 2>/dev/null || true)
  if [ -z "${pod_info}" ]; then
    echo "No gitlab-runner pods found yet. Retrying..."
  else
    if echo "${pod_info}" | grep -E ": .*true" >/dev/null 2>&1; then
      echo "Runner pods ready:"
      echo "${pod_info}"
      exit 0
    else
      echo "Runner pods not ready yet:" 
      echo "${pod_info}"
    fi
  fi
  sleep 5
done

echo "ERROR: Runner pods failed to reach ready state within ${TIMEOUT}s" >&2
echo "Last observed status:" >&2
echo "${pod_info}" >&2 || true
exit 2
