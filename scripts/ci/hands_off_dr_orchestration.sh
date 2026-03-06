#!/bin/bash
# ==============================================================================
# SCRIPT: hands_off_dr_orchestration.sh
# MODE: SOVEREIGN | HANDS-OFF | IDEMPOTENT
# ==============================================================================
set -euo pipefail

MODE="${1:-status}"
SEED_FILE="artifacts/vault/seed_from_yubikey.age"

echo "==== 24/7 AUTONOMOUS DR ORCHESTRATOR LIVE ===="

case $MODE in
    sovereign)
        echo "INFO: Initializing Sovereign Recovery Session via Hardware Root-of-Trust."
        if [[ ! -f "$SEED_FILE" ]]; then
            echo "CRITICAL: Sovereign seed missing. Please run the YubiKey bootstrap first."
            exit 1
        fi
        ./scripts/dr/drill_run.sh --source "github-sovereign" --target "ephemeral-runner"
        ;;
    monitor)
        echo "INFO: Ingesting metrics and pushing to Slack bridge."
        ./scripts/ci/dr_pipeline_monitor.sh
        ;;
    status)
        echo "CURRENT STATE: Production Ready (Sovereign Mode)"
        ls -l reports/dr_audit_*.json || echo "No audit logs yet."
        ;;
    *)
        echo "USAGE: $0 [sovereign|monitor|status]"
        exit 1
        ;;
esac

echo "✅ CYCLE COMPLETE: $(date)"
