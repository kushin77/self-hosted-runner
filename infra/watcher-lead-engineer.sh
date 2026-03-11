#!/usr/bin/env bash

# ============================================================================
# LEAD ENGINEER WATCHER - AUTONOMOUS TRIGGER
# ============================================================================
# Polls GSM for deployer-sa-key secret.
# Once key exists, automatically runs the lead engineer orchestrator.
# Immutable, idempotent, fully automated.
#
# Start this before Project Owner creates the key:
#   nohup bash infra/watcher-lead-engineer.sh &
#
# Once deployer-sa-key appears in GSM, orchestrator runs automatically.
# All logs preserved in /tmp for immutable audit trail.
#
# ============================================================================

set -euo pipefail

PROJECT=${PROJECT:-nexusshield-prod}
SECRET_NAME=deployer-sa-key
POLL_INTERVAL=${POLL_INTERVAL:-10}
MAX_WAIT_SECONDS=${MAX_WAIT_SECONDS:-900}  # 15 minutes

WATCHER_LOG=/tmp/watcher-lead-engineer-$(date +%Y%m%d-%H%M%S).log
ORCHESTRATOR_LOG=/tmp/orchestrator-run-$(date +%Y%m%d-%H%M%S).log

{
  echo "=========================================="
  echo "LEAD ENGINEER WATCHER started at $(date)"
  echo "Project: $PROJECT"
  echo "Secret: $SECRET_NAME"
  echo "Poll interval: ${POLL_INTERVAL}s"
  echo "Max wait: ${MAX_WAIT_SECONDS}s"
  echo "=========================================="
  echo ""

  ELAPSED=0
  FOUND=0

  while [ $ELAPSED -lt $MAX_WAIT_SECONDS ]; do
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Checking for $SECRET_NAME in GSM... (elapsed: ${ELAPSED}s)"

    if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
      echo ""
      echo "✅ SECRET FOUND: $SECRET_NAME"
      echo ""
      FOUND=1
      break
    fi

    echo "  ⏳ Not yet... sleeping ${POLL_INTERVAL}s"
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
  done

  echo ""

  if [ $FOUND -eq 0 ]; then
    echo "❌ TIMEOUT: Secret not found within ${MAX_WAIT_SECONDS}s"
    echo "   Please have Project Owner create the secret:"
    echo "   -> Run: bash infra/minimal-bootstrap-deployer.sh"
    echo "   or with full roles:"
    echo "   -> Run: bash infra/grant-orchestrator-roles.sh"
    exit 1
  fi

  echo "=========================================="
  echo "🚀 TRIGGERING ORCHESTRATOR at $(date)"
  echo "=========================================="
  echo ""

  # Run orchestrator with all output logged
  if bash /home/akushnir/self-hosted-runner/infra/lead-engineer-orchestrator.sh 2>&1 | tee -a "$ORCHESTRATOR_LOG"; then
    echo ""
    echo "✅ ORCHESTRATOR SUCCEEDED at $(date)"
    exit 0
  else
    echo ""
    echo "❌ ORCHESTRATOR FAILED - see $ORCHESTRATOR_LOG"
    exit 1
  fi

} | tee -a "$WATCHER_LOG"
