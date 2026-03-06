#!/bin/bash
set -euo pipefail
MODE="${1:-status}"
echo "==== 24/7 AUTONOMOUS DR ORCHESTRATOR LIVE ===="
case $MODE in
    sovereign) ./scripts/dr/drill_run.sh --source "github-sovereign" ;;
    monitor)   ./scripts/ci/dr_pipeline_monitor.sh ;;
    *)         echo "CURRENT STATE: Production Ready (Sovereign Mode)" ;;
esac
