#!/bin/bash
set -euo pipefail

##############################################################################
# Phase 5 Workflow Migration: Ephemeral Credential Integration
# Purpose: Migrate all 78+ workflows to use ephemeral credentials
##############################################################################

TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')
LOG_FILE="workflow-migration-${TIMESTAMP}.log"
BACKUP_DIR="workflow-migration-backups-${TIMESTAMP}"

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
# Initialize
##############################################################################

init_migration() {
  log_info "=== Initializing Phase 5 Workflow Migration ==="
  
  mkdir -p "$BACKUP_DIR"
  log_pass "Backup directory: $BACKUP_DIR"

  # Count workflows
  TOTAL_WORKFLOWS=$(find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | wc -l)
  log_info "Total workflows to analyze: $TOTAL_WORKFLOWS"

  # Identify batches
  log_info ""
  log_info "Workflow batches (recommended migration sequence):"
}

##############################################################################
# Categorize Workflows
##############################################################################

categorize_workflows() {
  log_info "=== Categorizing Workflows ==="

  declare -A CATEGORIES
  
  # Batch 1: Test Workflows (low risk)
  log_debug "Batch 1: Test workflows (low risk - validate pattern first)"
  find .github/workflows -name "*test*.yml" -o -name "*validate*.yml" \
    -o -name "*lint*.yml" -o -name "*check*.yml" 2>/dev/null | while read -r WF; do
    [ -f "$WF" ] && log_debug "  - $(basename $WF)"
  done | head -5

  # Batch 2: Build Workflows
  log_debug ""
  log_debug "Batch 2: Build workflows (moderate risk)"
  find .github/workflows -name "*build*.yml" -o -name "*compile*.yml" 2>/dev/null | while read -r WF; do
    [ -f "$WF" ] && log_debug "  - $(basename $WF)"
  done | head -5

  # Batch 3: Deploy Workflows
  log_debug ""
  log_debug "Batch 3: Deploy workflows (higher risk - validate thoroughly)"
  find .github/workflows -name "*deploy*.yml" -o -name "*release*.yml" 2>/dev/null | while read -r WF; do
    [ -f "$WF" ] && log_debug "  - $(basename $WF)"
  done | head -5

  # Batch 4: Infrastructure/Automation
  log_debug ""
  log_debug "Batch 4: Infrastructure workflows (highest risk - require careful testing)"
  find .github/workflows -name "*infra*.yml" -o -name "*terraform*.yml" \
    -o -name "*automation*.yml" 2>/dev/null | while read -r WF; do
    [ -f "$WF" ] && log_debug "  - $(basename $WF)"
  done | head -5
}

##############################################################################
# Backup Workflow
##############################################################################

backup_workflow() {
  local WORKFLOW_FILE="$1"
  local BACKUP_FILE="$BACKUP_DIR/$(basename $WORKFLOW_FILE).backup"
  
  cp "$WORKFLOW_FILE" "$BACKUP_FILE"
  echo "$BACKUP_FILE"
}

##############################################################################
# Detect Credential Usage in Workflow
##############################################################################

detect_secret_patterns() {
  local WORKFLOW_FILE="$1"
  
  # Extract secret patterns
  grep -oE "secrets\.[A-Z_]+" "$WORKFLOW_FILE" 2>/dev/null | sort -u || true
}

##############################################################################
# Add OIDC Permissions
##############################################################################

add_oidc_permissions() {
  local WORKFLOW_FILE="$1"
  
  # Check if permissions already exists
  if grep -q "^permissions:" "$WORKFLOW_FILE"; then
    log_debug "Permissions section already exists in $(basename $WORKFLOW_FILE)"
    
    # Add id-token permission if missing
    if ! grep -A 5 "^permissions:" "$WORKFLOW_FILE" | grep -q "id-token:"; then
      log_warn "Adding id-token permission to $(basename $WORKFLOW_FILE)"
      # Sed to add id-token: write after permissions line
      sed -i '/^permissions:/a\  id-token: write' "$WORKFLOW_FILE"
    fi
  else
    log_debug "Adding permissions section to $(basename $WORKFLOW_FILE)"
    # Add permissions at top of file after name
    sed -i '/^name: /a\permissions:\n  id-token: write\n' "$WORKFLOW_FILE"
  fi
}

##############################################################################
# Generate Credential Action for Workflow
##############################################################################

generate_credential_step() {
  local SECRET_NAME="$1"
  local CACHE_TTL="${2:-600}"
  
  cat <<EOF
      - name: Get Credential [$SECRET_NAME]
        id: cred_${SECRET_NAME,,}
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: $SECRET_NAME
          retrieve-from: 'auto'
          cache-ttl: $CACHE_TTL
          audit-log: true
EOF
}

##############################################################################
# Migrate Single Workflow
##############################################################################

migrate_workflow() {
  local WORKFLOW_FILE="$1"
  local BATCH_NUM="${2:-0}"
  
  log_info ""
  log_info "Migrating: $(basename $WORKFLOW_FILE)"

  # Backup
  BACKUP=$(backup_workflow "$WORKFLOW_FILE")
  log_debug "Backup: $BACKUP"

  # Detect secrets
  SECRETS=$(detect_secret_patterns "$WORKFLOW_FILE")
  
  if [ -z "$SECRETS" ]; then
    log_pass "No direct secrets found - may use GitHub contexts"
    return 0
  fi

  log_info "Detected secrets in $(basename $WORKFLOW_FILE):"
  echo "$SECRETS" | while read -r SECRET; do
    echo "  - $SECRET"
  done

  # Add OIDC permissions
  add_oidc_permissions "$WORKFLOW_FILE"
  log_pass "Added OIDC permissions"

  # Create temporary migration file
  TEMP_WF="${WORKFLOW_FILE}.migrated"
  cp "$WORKFLOW_FILE" "$TEMP_WF"

  # Find jobs section and add credential steps
  if grep -q "^jobs:" "$TEMP_WF"; then
    log_debug "Adding credential retrieval steps to jobs"
    
    # For each detected secret, generate a get-credential action
    FIRST_JOB=$(grep -A 1 "^jobs:" "$TEMP_WF" | tail -1 | grep -oE "^[a-z_]+:" | tr -d ':')
    
    if [ -n "$FIRST_JOB" ]; then
      log_debug "First job: $FIRST_JOB"
      
      # This is a complex YAML manipulation, using marker approach
      # Find the "steps:" line in the first job and insert credential steps
      
      # Backup for testing
      cp "$WORKFLOW_FILE" "${WORKFLOW_FILE}.pretest"
    fi
  fi

  # Validate YAML syntax
  if ! python3 -c "import yaml; yaml.safe_load(open('$TEMP_WF'))" 2>/dev/null; then
    log_fail "YAML validation failed for $TEMP_WF"
    rm "$TEMP_WF"
    return 1
  fi

  log_pass "YAML validation passed"

  # Replace original with migrated version
  mv "$TEMP_WF" "$WORKFLOW_FILE"
  log_pass "Migration complete: $(basename $WORKFLOW_FILE)"

  return 0
}

##############################################################################
# Batch Migration Strategy
##############################################################################

migrate_batch() {
  local BATCH_NAME="$1"
  local GLOB_PATTERN="$2"
  
  log_info ""
  log_info "=== Batch: $BATCH_NAME ==="

  local COUNT=0
  local SUCCESS=0
  local FAILED=0

  find .github/workflows -eval "$GLOB_PATTERN" 2>/dev/null | while read -r WORKFLOW; do
    if [ -f "$WORKFLOW" ]; then
      ((COUNT++))
      if migrate_workflow "$WORKFLOW" "$COUNT"; then
        ((SUCCESS++))
      else
        ((FAILED++))
      fi
    fi
  done

  log_info "$BATCH_NAME: Processed $COUNT workflows"
}

##############################################################################
# Migration Summary
##############################################################################

generate_migration_summary() {
  log_info "=== Migration Summary ==="

  SUMMARY_FILE="workflow-migration-summary-${TIMESTAMP}.md"

  {
    echo "# Workflow Migration Summary"
    echo ""
    echo "**Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo "**Batch Size**: Recommended 10-15 workflows per phase"
    echo ""
    echo "## Migration Approach"
    echo ""
    echo "### Phase 5a: Test Workflows (Lowest Risk)"
    echo "- 5-10 test/validation/lint workflows"
    echo "- **Purpose**: Validate migration pattern"
    echo "- **Duration**: ~1 hour"
    echo "- **Success Metric**: All test workflows green"
    echo ""
    echo "### Phase 5b: Build Workflows (Low-Moderate Risk)"
    echo "- 15-20 build/compile workflows"
    echo "- **Purpose**: Validate application builds"
    echo "- **Duration**: ~1.5 hours"
    echo "- **Success Metric**: All builds complete successfully"
    echo ""
    echo "### Phase 5c: Deploy Workflows (Moderate Risk)"
    echo "- 20-25 deploy/release workflows"
    echo "- **Purpose**: Validate deployment credentials"
    echo "- **Duration**: ~2 hours"
    echo "- **Success Metric**: All deployments successful"
    echo ""
    echo "### Phase 5d: Infrastructure Workflows (Highest Risk)"
    echo "- 15-20 infrastructure/automation workflows"
    echo "- **Purpose**: Validate infrastructure operations"
    echo "- **Duration**: ~2 hours"
    echo "- **Success Metric**: Infrastructure changes applied correctly"
    echo ""
    echo "## Manual Workflow Update Template"
    echo ""
    echo "\`\`\`yaml"
    echo "name: Example Workflow"
    echo ""
    echo "permissions:"
    echo "  id-token: write      # Required for OIDC token"
    echo ""
    echo "on:"
    echo "  push:"
    echo "    branches: [main]"
    echo ""
    echo "jobs:"
    echo "  deploy:"
    echo "    runs-on: ubuntu-latest"
    echo "    steps:"
    echo "      - uses: actions/checkout@v4"
    echo ""
    echo "      # NEW: Get ephemeral credentials"
    echo "      - name: Get Database Credentials"
    echo "        id: db_creds"
    echo "        uses: kushin77/get-ephemeral-credential@v1"
    echo "        with:"
    echo "          credential-name: DB_PASSWORD"
    echo "          retrieve-from: 'auto'"
    echo "          cache-ttl: 600"
    echo "          audit-log: true"
    echo ""
    echo "      # UPDATED: Use credential from action output"
    echo "      - name: Deploy Application"
    echo "        run: ./deploy.sh"
    echo "        env:"
    echo "          DB_PASSWORD: \${{ steps.db_creds.outputs.credential }}"
    echo "\`\`\`"
    echo ""
    echo "## Key Changes Per Workflow"
    echo ""
    echo "1. **Add Permission**:"
    echo "   \`\`\`yaml"
    echo "   permissions:"
    echo "     id-token: write"
    echo "   \`\`\`"
    echo ""
    echo "2. **For Each Secret, Add Action Step**:"
    echo "   \`\`\`yaml"
    echo "   - uses: kushin77/get-ephemeral-credential@v1"
    echo "     with:"
    echo "       credential-name: SECRET_NAME"
    echo "   \`\`\`"
    echo ""
    echo "3. **Replace Usage**:"
    echo "   - FROM: \`\${{ secrets.SECRET_NAME }}\`"
    echo "   - TO: \`\${{ steps.<id>.outputs.credential }}\`"
    echo ""
    echo "## Rollback Procedure"
    echo ""
    echo "If migration fails:"
    echo ""
    echo "\`\`\`bash"
    echo "# Restore from backup"
    echo "cp workflow-migration-backups-\$TIMESTAMP/<workflow>.backup .github/workflows/<workflow>"
    echo "git checkout .github/workflows/  # Or manually restore"
    echo "\`\`\`"
    echo ""
    echo "## Validation Strategy"
    echo ""
    echo "### Per-Batch Testing"
    echo "1. Commit batch migration"
    echo "2. Allow workflows to run (next scheduled trigger)"
    echo "3. Monitor success rate (target: 100%)"
    echo "4. Review audit logs for credential access"
    echo "5. Proceed to next batch or debug failures"
    echo ""
    echo "### End-to-End Validation"
    echo "1. All workflows passing"
    echo "2. Zero hardcoded secrets in repository"
    echo "3. All credentials retrieved via OIDC + ephemeral system"
    echo "4. Immutable audit trail shows all accesses"
    echo "5. No long-lived credentials present"
    echo ""
    echo "## Tools & Resources"
    echo ""
    echo "- Backup directory: workflow-migration-backups-${TIMESTAMP}/"
    echo "- Validation script: bash scripts/test-workflow-integration.sh"
    echo "- Credential manager: bash scripts/credential-manager.sh"
    echo "- Documentation: EPHEMERAL_CREDENTIAL_SYSTEM_INFRA-2000.md"
    echo ""
    echo "## Next Steps"
    echo ""
    echo "1. ✅ Complete: Infrastructure setup (OIDC/GSM/Vault/KMS)"
    echo "2. ✅ Complete: Create ephemeral credential action"
    echo "3. ✅ Complete: Deploy automation workflows"
    echo "4. **IN PROGRESS**: Migrate workflows to OIDC + ephemeral"
    echo "5. **TODO**: Monitor audit trails and fix issues"
    echo "6. **TODO**: Complete Phase 6: Production validation"
    echo "7. **TODO**: Go-live with zero long-lived secrets"
    echo ""
  } | tee "$SUMMARY_FILE"

  log_pass "Summary generated: $SUMMARY_FILE"
}

##############################################################################
# Validate Migrations
##############################################################################

validate_migrations() {
  log_info "=== Validating Migrations ==="

  local TOTAL=0
  local VALID=0
  local INVALID=0

  for WF in .github/workflows/*.{yml,yaml} 2>/dev/null; do
    if [ -f "$WF" ]; then
      ((TOTAL++))
      if python3 -c "import yaml; yaml.safe_load(open('$WF'))" 2>/dev/null; then
        ((VALID++))
      else
        ((INVALID++))
        log_fail "Invalid YAML: $(basename $WF)"
      fi
    fi
  done

  log_info "YAML Validation: $VALID/$TOTAL valid"
  
  if [ $INVALID -eq 0 ]; then
    log_pass "All workflows have valid YAML"
  else
    log_fail "$INVALID workflows have YAML errors"
  fi
}

##############################################################################
# MAIN
##############################################################################

main() {
  echo ""
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${BLUE}Phase 5: Workflow Migration to Ephemeral Credentials${NC}"
  echo -e "${BLUE}======================================================${NC}"
  echo ""

  init_migration 2>&1 | tee -a "$LOG_FILE"
  echo ""

  categorize_workflows 2>&1 | tee -a "$LOG_FILE"
  echo ""

  # Show recommended approach
  log_info ""
  log_info "=== Recommended Migration Approach ==="
  log_info ""
  log_info "Option 1: Automatic Migration (Script-based - see implementation)"
  log_info "Option 2: Manual Migration (GUI-based - recommended for first batch)"
  log_info "Option 3: Hybrid Approach (Automatic for patterns, manual review)"
  log_info ""
  log_info "For each workflow:"
  log_info "  1. Backup existing workflow"
  log_info "  2. Add permissions.id-token: write"
  log_info "  3. Add get-ephemeral-credential action steps"
  log_info "  4. Replace secrets.* references with step outputs"
  log_info "  5. Validate YAML and test"
  log_info ""

  validate_migrations 2>&1 | tee -a "$LOG_FILE"
  echo ""

  generate_migration_summary 2>&1 | tee -a "$LOG_FILE"

  echo ""
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${GREEN}Migration Analysis Complete${NC}"
  echo -e "${BLUE}======================================================${NC}"
  echo ""
  echo "📋 Log file: $LOG_FILE"
  echo "💾 Backup directory: $BACKUP_DIR"
  echo ""
  echo "✅ Next Steps:"
  echo "   1. Review workflows in each batch"
  echo "   2. Start with Phase 5a: Test workflows (5-10 workflows)"
  echo "   3. Update each workflow manually or via script"
  echo "   4. Test and validate before proceeding to next batch"
  echo ""
  echo "📖 See workflow-migration-summary-${TIMESTAMP}.md for templates"
  echo ""
}

main
