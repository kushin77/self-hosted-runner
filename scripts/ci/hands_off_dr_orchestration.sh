#!/usr/bin/env bash
# hands_off_dr_orchestration.sh — 24/7 Autonomous Disaster Recovery Orchestrator
#
# Purpose: This is the root-of-trust for the automated DR system. It coordinates
#          backups, GitHub mirroring, and quarterly dry-runs without human input.
#
# Principles: 
#   - IMMUTABLE: Everything versioned in Git; code is the source of truth.
#   - SOVEREIGN: Independent of any single provider; restorable from mirror.
#   - EPHEMERAL: Dry-runs use throwaway infrastructure (K3s/Vault).
#   - IDEMPOTENT: Safe to re-run; checks state before acting.
#
# Usage: 
#   Normally triggered by GitLab CI Schedule (Quarterly).
#   Can be run manually for on-demand validation.
#
# Requirements:
#   - gcloud CLI (GSM access)
#   - age (decryption)

set -euo pipefail

# 1. Environment & Secrets Setup
export SECRET_PROJECT="${SECRET_PROJECT:-gcp-eiq}"
echo "[$(date -Iseconds)] 🚀 Starting Autonomous DR Orchestration"

# 2. Pre-flight Component Check
./scripts/ci/dr_preflight_check.sh || {
    echo "❌ [$(date -Iseconds)] Pre-flight failed. Some DR components are missing or invalid."
    exit 1
}

# 3. Determine Mode (Identity-Validated or Simulation)
if gcloud secrets versions access latest --secret=gitlab-api-token --project="$SECRET_PROJECT" &>/dev/null; then
    echo "✅ [$(date -Iseconds)] GitLab API token found. Proceeding with IDENTITY-VALIDATED run."
    MODE="--live"
else
    echo "⚠ [$(date -Iseconds)] GitLab API token missing. Falling back to --simulate mode."
    MODE="--simulate"
fi

# 4. Execute DR Dry-Run
# This script handles the download, decrypt, restore, and metric logging.
./scripts/ci/run_dr_dryrun.sh $MODE

# 5. Monitor & Ingest Results
# Wait for the monitoring script to confirm success/failure and update Slack.
export MONITOR_LOG="/tmp/dr_dryrun_$(date +%Y%m%d).log"
if [[ -f "$MONITOR_LOG" ]]; then
    ./scripts/ci/ingest_dr_log_and_close_issues.sh "$MONITOR_LOG"
else
    # Fallback to general ingestion if specific log isn't found
    ./scripts/ci/ingest_dr_log_and_close_issues.sh "/tmp/dr_dryrun_simulate.log"
fi

# 6. Maintenance: Rotate Deploy Keys (If Token Present)
if [[ "$MODE" == "--live" ]]; then
    echo "[$(date -Iseconds)] 🔒 Rotating GitHub Mirror Deploy Keys"
    ./scripts/ci/rotate_github_deploy_key.sh
fi

echo "[$(date -Iseconds)] ✅ Autonomous DR Orchestration Complete."
echo "----------------------------------------------------------------"
echo "Metrics and Runbook: docs/DR_RUNBOOK.md"
echo "Stakeholder Notifications: Posted to Slack (#dr-automation)"
