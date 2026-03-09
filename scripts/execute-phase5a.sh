#!/bin/bash
set -euo pipefail

##############################################################################
# Phase 5a Execution: Automated Test Workflow Migration
# Purpose: Migrate first batch of test workflows to ephemeral credentials
##############################################################################

TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')
LOG_FILE="phase5a-execution-${TIMESTAMP}.log"
BACKUP_DIR="phase5a-backups-${TIMESTAMP}"
EXECUTED_WORKFLOWS=()
MODIFIED_WORKFLOWS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"; }

##############################################################################
# Migrate Single Workflow: Intelligent Approach
##############################################################################

migrate_workflow_smart() {
  local WF_PATH="$1"
  local WF_NAME=$(basename "$WF_PATH")
  
  log_info ""
  log_info "Processing: $WF_NAME"

  # Create backup
  cp "$WF_PATH" "$BACKUP_DIR/${WF_NAME}.backup"
  log_debug "Backup created: $BACKUP_DIR/${WF_NAME}.backup"

  # Read file
  local CONTENT=$(cat "$WF_PATH")
  local MODIFIED=false
  local TEMP_FILE="${WF_PATH}.tmp"
  cp "$WF_PATH" "$TEMP_FILE"

  # Step 1: Add permissions if missing
  if ! grep -q "^permissions:" "$TEMP_FILE"; then
    log_debug "Adding permissions section..."
    sed -i '/^name: /a\permissions:\n  id-token: write\n' "$TEMP_FILE"
    MODIFIED=true
  elif ! grep -A 2 "^permissions:" "$TEMP_FILE" | grep -q "id-token:"; then
    log_debug "Adding id-token permission..."
    sed -i '/^permissions:/a\  id-token: write' "$TEMP_FILE"
    MODIFIED=true
  fi

  # Step 2: Detect secret patterns
  local SECRETS=$(grep -oE "secrets\.[A-Z_0-9]+" "$TEMP_FILE" | sort -u || true)
  
  if [ -z "$SECRETS" ]; then
    log_pass "No direct secrets found (already good)"
    rm "$TEMP_FILE"
    return 0
  fi

  log_info "Found secrets: $(echo "$SECRETS" | tr '\n' ' ')"

  # Step 3: For each secret, add retrieval step
  # Extract jobs section and add credential steps before first run command
  if grep -q "^\s*run:" "$TEMP_FILE"; then
    log_debug "Adding credential retrieval steps..."
    
    # Build credential retrieval script
    local CRED_STEPS=""
    local STEP_COUNTER=0
    
    while IFS= read -r SECRET; do
      [ -z "$SECRET" ] && continue
      
      local SECRET_NAME="${SECRET#secrets.}"
      local STEP_ID="cred_${SECRET_NAME,,}"
      local STEP_NUM=$((STEP_COUNTER + 1))
      
      CRED_STEPS="${CRED_STEPS}
      - name: Get Credential [$SECRET_NAME] (Step $STEP_NUM)
        id: $STEP_ID
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: $SECRET_NAME
          retrieve-from: 'auto'
          cache-ttl: 600
          audit-log: true"
      
      # Replace secret reference with step output
      sed -i "s|\${{ secrets\\.${SECRET_NAME} }}|\${{ steps.${STEP_ID}.outputs.credential }}|g" "$TEMP_FILE"
      
      ((STEP_COUNTER++))
    done <<< "$SECRETS"
    
    # Insert credential steps before first "run:" in workflow
    # Find line number of first run: and insert before it
    local FIRST_RUN_LINE=$(grep -n "^\s*run:" "$TEMP_FILE" | head -1 | cut -d: -f1)
    if [ -n "$FIRST_RUN_LINE" ]; then
      # Use awk to insert before line
      awk -v line=$FIRST_RUN_LINE -v creds="$CRED_STEPS" 'NR==line {print creds} {print}' "$TEMP_FILE" > "${TEMP_FILE}.new"
      mv "${TEMP_FILE}.new" "$TEMP_FILE"
      MODIFIED=true
      log_debug "Credential steps added ($STEP_COUNTER total)"
    else
      log_warn "Could not find run: in workflow, skipping credential insertion"
    fi
  fi

  # Step 4: Validate YAML
  if ! python3 -c "import yaml; yaml.safe_load(open('$TEMP_FILE'))" 2>/dev/null; then
    log_fail "YAML validation failed, reverting changes"
    rm "$TEMP_FILE"
    return 1
  fi

  # Step 5: Replace file and record
  if [ "$MODIFIED" = true ]; then
    mv "$TEMP_FILE" "$WF_PATH"
    MODIFIED_WORKFLOWS+=("$WF_NAME")
    log_pass "Migration complete: $WF_NAME"
    return 0
  else
    rm "$TEMP_FILE"
    log_pass "No changes needed: $WF_NAME (already has permissions)"
    return 0
  fi
}

##############################################################################
# Find and Migrate All Test Workflows
##############################################################################

migrate_test_workflows() {
  log_info "=== Phase 5a: Test Workflow Migration ==="
  log_info ""
  log_info "Finding test workflows (lint, validate, check, health-check)..."
  
  mkdir -p "$BACKUP_DIR"
  
  # Find test workflows
  local test_workflows=$(find .github/workflows -type f \( \
    -name "*test*.yml" -o \
    -name "*lint*.yml" -o \
    -name "*validate*.yml" -o \
    -name "*check*.yml" \
  \) | sort)
  
  local count=0
  while IFS= read -r WF; do
    [ -z "$WF" ] && continue
    ((count++))
    
    if migrate_workflow_smart "$WF"; then
      EXECUTED_WORKFLOWS+=("$(basename $WF)")
    fi
  done <<< "$test_workflows"
  
  log_info ""
  log_pass "Processed $count test workflows"
}

##############################################################################
# Generate Execution Report
##############################################################################

generate_report() {
  log_info ""
  log_info "=== Phase 5a Execution Report ==="
  
  REPORT_FILE="phase5a-execution-report-${TIMESTAMP}.md"
  
  {
    echo "# Phase 5a Execution Report"
    echo ""
    echo "**Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo "**Batch**: Phase 5a - Test Workflows (Low Risk)"
    echo ""
    echo "## Summary"
    echo ""
    echo "Successfully migrated test workflows to ephemeral credential retrieval."
    echo ""
    echo "**Statistics**:"
    echo "- Total workflows processed: ${#EXECUTED_WORKFLOWS[@]}"
    echo "- Workflows modified: ${#MODIFIED_WORKFLOWS[@]}"
    echo "- Backup location: $BACKUP_DIR"
    echo ""
    echo "## Workflows Migrated"
    echo ""
    for WF in "${MODIFIED_WORKFLOWS[@]}"; do
      echo "- ✅ $WF"
    done
    echo ""
    echo "## Changes Made"
    echo ""
    echo "**Per Workflow**:"
    echo "1. ✅ Added \`permissions.id-token: write\` for OIDC"
    echo "2. ✅ Added \`get-ephemeral-credential@v1\` action steps for each secret"
    echo "3. ✅ Updated env var references from \`secrets.*\` to \`steps.id.outputs.credential\`"
    echo "4. ✅ Validated YAML syntax"
    echo "5. ✅ Backed up original workflows (rollback available)"
    echo ""
    echo "## Next Steps"
    echo ""
    echo "1. Commit changes: \`git add .github/workflows/ && git commit ...\`"
    echo "2. Push to repository: \`git push\`"
    echo "3. Monitor workflows: Watch GitHub Actions for success"
    echo "4. If all pass: Proceed to Phase 5b (build workflows)"
    echo "5. If failed: Restore from \`$BACKUP_DIR/\`"
    echo ""
    echo "## Validation"
    echo ""
    echo "**Pre-commit Checks**:"
    echo "\`\`\`bash"
    echo "# Count remaining direct secret references"
    echo "grep -r 'secrets\.' .github/workflows/ | wc -l"
    echo ""
    echo "# Should show 0 or only GITHUB_TOKEN (automatic context)"
    echo "\`\`\`"
    echo ""
    echo "## Rollback (if needed)"
    echo ""
    echo "\`\`\`bash"
    echo "cp $BACKUP_DIR/* .github/workflows/"
    echo "git checkout .github/workflows/"
    echo "\`\`\`"
    echo ""
    echo "---"
    echo ""
    echo "**Status**: Ready for commit and testing"
    echo "**Execution Time**: Phase 5a complete"
    echo "**Next Phase**: Phase 5b (Build Workflows)"
    echo ""
  } | tee "$REPORT_FILE"
  
  log_pass "Report generated: $REPORT_FILE"
}

##############################################################################
# MAIN
##############################################################################

main() {
  echo ""
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${BLUE}Phase 5a: Automated Test Workflow Migration${NC}"
  echo -e "${BLUE}======================================================${NC}"
  echo ""

  log_info "Starting Phase 5a execution..."
  log_info "Timestamp: $TIMESTAMP"
  log_info "Log file: $LOG_FILE"

  migrate_test_workflows 2>&1 | tee -a "$LOG_FILE"
  
  generate_report 2>&1 | tee -a "$LOG_FILE"

  echo ""
  echo -e "${BLUE}======================================================${NC}"
  if [ ${#MODIFIED_WORKFLOWS[@]} -gt 0 ]; then
    echo -e "${GREEN}Phase 5a COMPLETE: ${#MODIFIED_WORKFLOWS[@]} workflows migrated${NC}"
  else
    echo -e "${YELLOW}Phase 5a: Already migrated (no changes needed)${NC}"
  fi
  echo -e "${BLUE}======================================================${NC}"
  echo ""
  
  # Show next actions
  if [ ${#MODIFIED_WORKFLOWS[@]} -gt 0 ]; then
    echo "✅ Next Action: Commit these changes"
    echo ""
    echo "  git add .github/workflows/"
    echo "  git commit -m 'Phase 5a: Migrate test workflows to ephemeral credentials'"
    echo ""
  fi
}

main
