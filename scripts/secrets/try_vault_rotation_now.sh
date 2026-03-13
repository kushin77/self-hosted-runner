#!/usr/bin/env bash
set -euo pipefail

GSM_PROJECT=${GSM_PROJECT:-nexusshield-prod}
ISSUE_NUMBER=${ISSUE_NUMBER:-2919}
LOG=logs/rotate-vault-try-$(date -u +%Y%m%dT%H%M%SZ).log

echo "Starting vault rotation attempt at $(date -u)" | tee -a "$LOG"
if bash scripts/secrets/run_vault_rotation.sh > >(tee -a "$LOG") 2>&1; then
  echo "Vault rotation succeeded at $(date -u)" | tee -a "$LOG"
  gh issue comment "$ISSUE_NUMBER" --body "Vault rotation succeeded. See attached log in repo: $LOG" || true
  exit 0
else
  echo "Vault rotation failed at $(date -u)" | tee -a "$LOG"
  # Save summary report
  cat > reports/VaultRotationAttempt_$(date -u +%Y%m%dT%H%M%SZ).md <<EOF
# Vault Rotation Attempt Report

Timestamp: $(date -u)

Result: FAILED

See log: $LOG
EOF
  gh issue comment "$ISSUE_NUMBER" --body-file reports/VaultRotationAttempt_$(date -u +%Y%m%dT%H%M%SZ).md || true
  exit 1
fi
