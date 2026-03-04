#!/usr/bin/env bash
set -euo pipefail

# Simple unit test harness for runner_health_monitor.sh
# Mocks safe_ssh and gh_api to simulate healthy/failed runners.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/runner_health_monitor.sh"

if [ ! -f "$SCRIPT" ]; then
    echo "Script not found: $SCRIPT" >&2
    exit 2
fi

export SKIP_MAIN=1
source "$SCRIPT"

# Mock get_runner_systemd_services/check_runner_service_status/get_runner_service_status
# directly to avoid ssh/gh interaction in unit tests.
get_runner_systemd_services() {
    echo "actions.runner.example.service"
}

check_runner_service_status() {
    # always healthy
    return 0
}

get_runner_service_status() {
    echo "Active: active (running)"; echo "Main PID: 1234"
}

# Mock gh_api to return one runner and report it online
gh_api() {
    # If querying a specific runner id, return its status
    if [[ "$*" == *"/actions/runners/"* ]]; then
        echo "online"
        return 0
    fi

    # If listing runners, return a single JSON object per line
    if [[ "$*" == *"/actions/runners"* ]]; then
        echo '{"id": 1, "name": "example-runner"}'
        return 0
    fi

    return 0
}

echo "Running unit test: health_check (host mode, mocked)"
RUN_MODE=host
if health_check; then
    echo "PASS: health_check returned success"
    exit 0
else
    echo "FAIL: health_check returned failure" >&2
    exit 1
fi
