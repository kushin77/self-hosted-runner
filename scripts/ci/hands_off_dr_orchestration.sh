#!/bin/bash
set -euo pipefail
echo "==== 24/7 AUTONOMOUS DR ORCHESTRATOR LIVE ===="
case "${1:-status}" in
    sovereign) ./scripts/dr/drill_run.sh --source "github-sovereign" ;;
    monitor)   ./scripts/ci/dr_pipeline_monitor.sh ;;
    *)         echo "ACTIVE: Waiting for YubiKey Bootstrap..." ;;
esac
