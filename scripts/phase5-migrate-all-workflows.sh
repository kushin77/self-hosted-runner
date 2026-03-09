#!/bin/bash
set -euo pipefail

##############################################################################
# Phase 5: All-In-One Workflow Migration (Aggressive Mode)
# Migrate all 56+ workflows with direct secrets to ephemeral credentials
##############################################################################

TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')
LOG_FILE="phase5-migration-full-${TIMESTAMP}.log"
BACKUP_DIR="workflows-backup-${TIMESTAMP}"
STATS_FILE="phase5-stats-${TIMESTAMP}.json"

# Tracking
TOTAL_WF=0
MODIFIED_WF=0
FAILED_WF=0
declare -a MODIFIED_LIST
declare -a FAILED_LIST

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"; }

##############################################################################
# Stage 1: Add Permissions to All Workflows
##############################################################################

add_permissions_to_all() {
  log_info "=== STAGE 1: Adding OIDC Permissions ==="
  
  for wf in .github/workflows/*.yml; do
    [ ! -f "$wf" ] && continue
    
    # Check if permissions already set
    if ! grep -q "^permissions:" "$wf"; then
      # Add after 'name:' line
      sed -i '/^name: /a\permissions:\n  id-token: write' "$wf"
      log_pass "$(basename $wf): Added permissions"
    elif ! grep -A 2 "^permissions:" "$wf" | grep -q "id-token:"; then
      # Add id-token to existing permissions
      sed -i '/^permissions:/a\  id-token: write' "$wf"
      log_pass "$(basename $wf): Updated permissions"
    fi
  done
}

##############################################################################
# Stage 2: Add Credential Retrieval Steps
##############################################################################

add_credential_steps() {
  log_info ""
  log_info "=== STAGE 2: Adding Credential Retrieval Steps ==="
  
  for wf in .github/workflows/*.yml; do
    [ ! -f "$wf" ] && continue
    
    ((TOTAL_WF++))
    WF_NAME=$(basename "$wf")
    
    # Backup
    mkdir -p "$BACKUP_DIR"
    cp "$wf" "$BACKUP_DIR/${WF_NAME}.backup"
    
    # Extract secrets from this workflow
    SECRETS=$(grep -oE "secrets\.[A-Z_][A-Z0-9_]*" "$wf" | sort -u | sed 's/secrets\.//')
    
    if [ -z "$SECRETS" ]; then
      log_pass "$WF_NAME: No direct secrets (skipped)"
      continue
    fi
    
    log_info "Processing $WF_NAME..."
    
    # Build credential actions for each secret
    TEMP_FILE="${wf}.tmp"
    cp "$wf" "$TEMP_FILE"
    
    # For each secret, add retrieval step and replace references
    while IFS= read -r SECRET; do
      [ -z "$SECRET" ] && continue
      
      STEP_ID="cred_${SECRET,,}"
      
      # Add replacement sed command to TEMP_FILE at first occurrence of "steps:"
      # This adds credential retrieval before first run command
      STEP_YAML="      - name: Get Credential [$SECRET]
        id: $STEP_ID
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: $SECRET
          retrieve-from: 'auto'
          cache-ttl: 600
          audit-log: true"
      
      # Insert credentials block after jobs section opens and before first run
      # Using a marker approach
      if ! grep -q "END_CREDENTIAL_STEPS_$SECRET" "$TEMP_FILE"; then
        # Find first 'run:' line and insert credential steps before it
        FIRST_RUN=$(grep -n "run:" "$TEMP_FILE" | head -1 | cut -d: -f1)
        if [ -n "$FIRST_RUN" ]; then
          # Use awk to insert
          awk -v line=$FIRST_RUN -v cred="$STEP_YAML
        " 'NR==line {print cred} {print}' "$TEMP_FILE" > "${TEMP_FILE}.new"
          mv "${TEMP_FILE}.new" "$TEMP_FILE"
        fi
      fi
      
      # Replace secret reference with step output
      sed -i "s|\${{ secrets\.${SECRET} }}|\${{ steps.${STEP_ID}.outputs.credential }}|g" "$TEMP_FILE"
      
      log_debug "$WF_NAME: Added credential retrieval for $SECRET"
      
    done <<< "$SECRETS"
    
    # Validate YAML (basic check)
    if  head -50 "$TEMP_FILE" 2>/dev/null | grep -q "^name:"; then
      mv "$TEMP_FILE" "$wf"
      MODIFIED_LIST+=("$WF_NAME")
      ((MODIFIED_WF++))
      log_pass "$WF_NAME: ✅ MIGRATED"
    else
      rm "$TEMP_FILE"
      FAILED_LIST+=("$WF_NAME")
      ((FAILED_WF++))
      log_fail "$WF_NAME: YAML validation failed"
    fi
  done
}

##############################################################################
# Stage 3: Report & Statistics
##############################################################################

generate_stats() {
  log_info ""
  log_info "============================"
  log_info "Phase 5 Migration Complete"
  log_info "============================"
  log_info "Total workflows processed: $TOTAL_WF"
  log_info "Workflows modified: $MODIFIED_WF"
  log_info "Failed: $FAILED_WF"
  log_info "Backup directory: $BACKUP_DIR"
  
  # JSON stats
  {
    echo "{"
    echo '  "timestamp": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'", '
    echo '  "total_processed": '$TOTAL_WF', '
    echo '  "modified": '$MODIFIED_WF', '
    echo '  "failed": '$FAILED_WF', '
    echo '  "backup_dir": "'$BACKUP_DIR'", '
    echo '  "modified_workflows": ['
    printf '%s\n' "${MODIFIED_LIST[@]}" | jq -R . | paste -sd, - | sed 's/,$//'
    echo '  ], '
    echo '  "failed_workflows": ['
    printf '%s\n' "${FAILED_LIST[@]}" | jq -R . | paste -sd, - | sed 's/,$//'
    echo '  ]'
    echo "}"
  } | tee "$STATS_FILE"
}

##############################################################################
# MAIN
##############################################################################

main() {
  echo "" | tee "$LOG_FILE"
  echo -e "${BLUE}=================================================${NC}" | tee -a "$LOG_FILE"
  echo -e "${BLUE}Phase 5: Full Workflow Migration (All 88 Workflows)${NC}" | tee -a "$LOG_FILE"
  echo -e "${BLUE}Target: 56+ workflows with direct secrets${NC}" | tee -a "$LOG_FILE"
  echo -e "${BLUE}=================================================${NC}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  
  # Execute stages
  add_permissions_to_all 2>&1 | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  
  add_credential_steps 2>&1 | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  
  generate_stats 2>&1 | tee -a "$LOG_FILE"
  
  echo "" | tee -a "$LOG_FILE"
  echo -e "${GREEN}✅ PHASE 5 MIGRATION COMPLETE${NC}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  echo "Next Steps:" | tee -a "$LOG_FILE"
  echo "1. Review changes: git diff .github/workflows/" | tee -a "$LOG_FILE"
  echo "2. Test workflows: git push to trigger GitHub Actions" | tee -a "$LOG_FILE"
  echo "3. Monitor success rates in GitHub Actions" | tee -a "$LOG_FILE"
  echo "4. Proceed to Phase 6: Production validation" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  echo "Stats file: $STATS_FILE" | tee -a "$LOG_FILE"
  echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
  echo "Backups: $BACKUP_DIR/" | tee -a "$LOG_FILE"
}

main "$@"
