#!/usr/bin/env bash
set -euo pipefail

# Test k8s health check by mocking safe_kubectl output
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/runner_health_monitor.sh"

if [ ! -f "$SCRIPT" ]; then
    echo "Script not found: $SCRIPT" >&2
    exit 2
fi

export SKIP_MAIN=1
source "$SCRIPT"

# Mock safe_kubectl to return a single unhealthy pod
safe_kubectl() {
    if [[ "$*" == "get pods --all-namespaces -o json"* ]] || [[ "$*" == "get pods --all-namespaces -o json" ]]; then
        cat <<'JSON'
{
  "items": [
    {
      "metadata": {"namespace": "default", "name": "actions-runner-xyz"},
      "status": {"phase": "CrashLoopBackOff", "conditions": [{"type":"Ready","status":"False"}]}
    }
  ]
}
JSON
        return 0
    fi

    if [[ "$*" == "-n default logs --tail=200 actions-runner-xyz" ]] || [[ "$*" == *"logs --tail=200"* ]]; then
        echo "Simulated logs: crashloop reason";
        return 0
    fi

    if [[ "$*" == "-n default delete pod actions-runner-xyz --ignore-not-found" ]] || [[ "$*" == *"delete pod"* ]]; then
        echo "pod deleted"; return 0
    fi

    return 0
}

echo "Running unit test: k8s health_check (mocked)"
RUN_MODE=k8s
if health_check; then
    echo "PASS: k8s health_check returned success"
    exit 0
else
    echo "FAIL: k8s health_check returned failure" >&2
    exit 1
fi
