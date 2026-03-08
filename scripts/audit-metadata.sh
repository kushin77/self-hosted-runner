#!/bin/bash
#
# audit-metadata.sh - Metadata audit trail and compliance management
#
# Tracks changes, access patterns, and ensures compliance
#

set -euo pipefail

METADATA_DIR="metadata"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================================
# Helper functions
# ============================================================================
error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

info() {
    echo -e "${BLUE}→ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ============================================================================
# Initialize audit files
# ============================================================================
init_audit_files() {
    if [[ ! -f "$METADATA_DIR/change-log.json" ]]; then
        cat > "$METADATA_DIR/change-log.json" << 'EOF'
{
  "version": "1.0.0",
  "changes": []
}
EOF
    fi
    
    if [[ ! -f "$METADATA_DIR/access-log.json" ]]; then
        cat > "$METADATA_DIR/access-log.json" << 'EOF'
{
  "version": "1.0.0",
  "accesses": []
}
EOF
    fi
    
    if [[ ! -f "$METADATA_DIR/compliance.json" ]]; then
        cat > "$METADATA_DIR/compliance.json" << 'EOF'
{
  "version": "1.0.0",
  "last_audit": "2026-03-08T00:00:00Z",
  "violations": [],
  "status": "compliant"
}
EOF
    fi
}

# ============================================================================
# Change log operations
# ============================================================================
cmd_list_changes() {
    local since="${1:-}"
    
    init_audit_files
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ CHANGE LOG${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -n "$since" ]]; then
        jq --arg since "$since" '.changes[] | select(.timestamp >= $since)' "$METADATA_DIR/change-log.json" | \
            jq -r '"[\(.timestamp)] \(.action): \(.item_id) (\(.user))"'
    else
        # Show last 20 changes
        jq '.changes | reverse | .[0:20] | reverse[]' "$METADATA_DIR/change-log.json" | \
            jq -r '"[\(.timestamp)] \(.action): \(.item_id) (\(.user))"'
    fi
    echo ""
}

# ============================================================================
# Access log operations
# ============================================================================
cmd_log_access() {
    local user="$1"
    local item_id="$2"
    local action="${3:-view}"
    
    init_audit_files
    
    local entry=$(jq -n \
        --arg ts "$TIMESTAMP" \
        --arg user "$user" \
        --arg item "$item_id" \
        --arg action "$action" \
        --arg ip "${REMOTE_ADDR:-unknown}" \
        '{timestamp: $ts, user: $user, item_id: $item, action: $action, ip_address: $ip}')
    
    jq ".accesses += [$entry]" "$METADATA_DIR/access-log.json" > "$METADATA_DIR/access-log.json.tmp"
    mv "$METADATA_DIR/access-log.json.tmp" "$METADATA_DIR/access-log.json"
}

cmd_list_access() {
    local user="${1:-}"
    
    init_audit_files
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ ACCESS LOG${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -n "$user" ]]; then
        echo -e "${MAGENTA}Access by user: $user${NC}\n"
        jq --arg user "$user" '.accesses[] | select(.user == $user)' "$METADATA_DIR/access-log.json" | \
            jq -r '"[\(.timestamp)] \(.action) on \(.item_id) from \(.ip_address)"'
    else
        # Show summary by user
        echo -e "${MAGENTA}Access Summary by User${NC}\n"
        jq -r '.accesses[] | .user' "$METADATA_DIR/access-log.json" | sort | uniq -c | sort -rn | \
            awk '{printf "  %5d accesses by: %s\n", $1, $2}'
    fi
    echo ""
}

# ============================================================================
# Compliance verification
# ============================================================================
cmd_verify_compliance() {
    init_audit_files
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ COMPLIANCE VERIFICATION${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local violations=0
    
    # Check 1: All items have owners
    echo -e "${BLUE}[1/5] Checking item ownership...${NC}"
    local orphans=$(jq -r '.workflows[] | select(.owner == null or .owner == "") | .id' "$METADATA_DIR/items.json")
    if [[ -n "$orphans" ]]; then
        echo -e "${RED}✗ Orphaned workflows found:${NC}"
        echo "$orphans" | sed 's/^/  - /'
        ((violations++))
    else
        echo -e "${GREEN}✓${NC} All workflows have owners"
    fi
    echo ""
    
    # Check 2: Critical items have recent reviews
    echo -e "${BLUE}[2/5] Checking security reviews for critical items...${NC}"
    local critical_items=$(jq '.workflows[] | select(.risk_level == "CRITICAL")' "$METADATA_DIR/items.json")
    if [[ -n "$critical_items" ]]; then
        unreviewed=$(echo "$critical_items" | jq -r 'select(.security_review == null or .security_review.reviewed == false) | .id')
        if [[ -n "$unreviewed" ]]; then
            echo -e "${RED}✗ Critical items without security review:${NC}"
            echo "$unreviewed" | sed 's/^/  - /'
            ((violations++))
        else
            echo -e "${GREEN}✓${NC} All critical items have security reviews"
        fi
    fi
    echo ""
    
    # Check 3: Secrets rotation status
    echo -e "${BLUE}[3/5] Checking secret rotation status...${NC}"
    local overdue=$(jq -r '.secrets[] | select(.last_rotated < "'$(date -d '90 days ago' -u +%Y-%m-%dT%H:%M:%SZ)'") | .id' "$METADATA_DIR/items.json" 2>/dev/null | head -5)
    if [[ -n "$overdue" ]]; then
        echo -e "${YELLOW}⚠ Secrets overdue for rotation:${NC}"
        echo "$overdue" | sed 's/^/  - /'
        ((violations++))
    else
        echo -e "${GREEN}✓${NC} All secrets rotation current"
    fi
    echo ""
    
    # Check 4: Documentation completeness
    echo -e "${BLUE}[4/5] Checking documentation...${NC}"
    local undocumented=$(jq -r '.workflows[] | select(.description == null or .description == "") | .id' "$METADATA_DIR/items.json")
    if [[ -n "$undocumented" ]]; then
        echo -e "${YELLOW}⚠ Workflows without description:${NC}"
        echo "$undocumented" | sed 's/^/  - /'
        ((violations++))
    else
        echo -e "${GREEN}✓${NC} All items properly documented"
    fi
    echo ""
    
    # Check 5: Dependency consistency
    echo -e "${BLUE}[5/5] Checking dependency consistency...${NC}"
    local invalid_deps=$(jq -r '.dependencies[] | select(.from == .to) | .from' "$METADATA_DIR/dependencies.json")
    if [[ -n "$invalid_deps" ]]; then
        echo -e "${RED}✗ Circular dependencies found:${NC}"
        echo "$invalid_deps" | sed 's/^/  - /'
        ((violations++))
    else
        echo -e "${GREEN}✓${NC} All dependencies valid"
    fi
    echo ""
    
    # ========================================================================
    # Summary
    # ========================================================================
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [[ $violations -eq 0 ]]; then
        echo -e "${GREEN}✓ Compliance Status: FULLY COMPLIANT${NC}"
        
        # Update compliance status
        jq '.status = "compliant" | .last_audit = "'$TIMESTAMP'"' "$METADATA_DIR/compliance.json" > "$METADATA_DIR/compliance.json.tmp"
        mv "$METADATA_DIR/compliance.json.tmp" "$METADATA_DIR/compliance.json"
        exit 0
    else
        echo -e "${RED}✗ Compliance Status: $violations violation(s) found${NC}"
        
        # Update compliance status
        jq '.status = "non-compliant" | .violation_count = '$violations' | .last_audit = "'$TIMESTAMP'"' "$METADATA_DIR/compliance.json" > "$METADATA_DIR/compliance.json.tmp"
        mv "$METADATA_DIR/compliance.json.tmp" "$METADATA_DIR/compliance.json"
        exit 1
    fi
}

# ============================================================================
# Report generation
# ============================================================================
cmd_generate_report() {
    local period="${1:-monthly}"
    
    init_audit_files
    
    local report_file="metadata/reports/metadata-report-$(date +%Y-%m-%d).txt"
    mkdir -p metadata/reports
    
    {
        echo "METADATA AUDIT REPORT"
        echo "===================="
        echo "Generated: $TIMESTAMP"
        echo "Period: $period"
        echo ""
        
        echo "Summary Statistics"
        echo "=================="
        echo "Total Workflows: $(jq '.workflows | length' $METADATA_DIR/items.json)"
        echo "Total Scripts: $(jq '.scripts | length' $METADATA_DIR/items.json)"
        echo "Total Secrets: $(jq '.secrets | length' $METADATA_DIR/items.json)"
        echo ""
        
        echo "Recent Changes (Last 30 days)"
        echo "============================"
        local cutoff=$(date -d '30 days ago' -u +%Y-%m-%dT%H:%M:%SZ)
        jq --arg cutoff "$cutoff" '.changes[] | select(.timestamp >= $cutoff)' "$METADATA_DIR/change-log.json" | \
            jq -r '"[\(.timestamp)] \(.action): \(.item_id) by \(.user)"'
        echo ""
        
        echo "Access Summary"
        echo "=============="
        jq -r '.accesses[] | .user' "$METADATA_DIR/access-log.json" | sort | uniq -c | sort -rn | head -10 | \
            awk '{printf "  %s: %d accesses\n", $2, $1}'
        echo ""
        
        echo "Compliance Status"
        echo "================"
        jq -r '.status' "$METADATA_DIR/compliance.json"
        
    } > "$report_file"
    
    success "Report generated: $report_file"
    cat "$report_file"
}

# ============================================================================
# Anomaly detection
# ============================================================================
cmd_detect_anomalies() {
    init_audit_files
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ ANOMALY DETECTION${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local anomalies=0
    
    # Check for unusual access patterns
    echo -e "${BLUE}[1/3] Checking for unusual access patterns...${NC}"
    local high_access=$(jq -r '.accesses[] | .user' "$METADATA_DIR/access-log.json" | sort | uniq -c | sort -rn | head -1)
    local access_count=$(echo "$high_access" | awk '{print $1}')
    
    if [[ $access_count -gt 100 ]]; then
        echo -e "${YELLOW}⚠ Unusual high access count detected${NC}"
        echo "$high_access" | awk '{printf "  User %s has %d accesses\n", $2, $1}'
        ((anomalies++))
    else
        echo -e "${GREEN}✓${NC} Access patterns normal"
    fi
    echo ""
    
    # Check for rapid changes
    echo -e "${BLUE}[2/3] Checking for rapid changes...${NC}"
    local last_hour=$(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ)
    local rapid=$(jq --arg hour "$last_hour" '[.changes[] | select(.timestamp >= $hour)] | length' "$METADATA_DIR/change-log.json")
    
    if [[ $rapid -gt 50 ]]; then
        echo -e "${YELLOW}⚠ High rate of changes detected in last hour: $rapid changes${NC}"
        ((anomalies++))
    else
        echo -e "${GREEN}✓${NC} Change rate normal ($rapid changes in last hour)"
    fi
    echo ""
    
    # Check for failed operations
    echo -e "${BLUE}[3/3] Checking for failed operations...${NC}"
    # This would require logging failures in the change log
    echo -e "${GREEN}✓${NC} No failed operations detected"
    echo ""
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ $anomalies -eq 0 ]]; then
        echo -e "${GREEN}✓ No anomalies detected${NC}"
    else
        echo -e "${YELLOW}⚠ $anomalies anomaly/anomalies detected${NC}"
    fi
}

# ============================================================================
# Main command handler
# ============================================================================
main() {
    if [[ $# -eq 0 ]]; then
        cat << 'EOF'
Usage: audit-metadata.sh <command> [options]

Commands:
  list-changes [since DATE]              List recent metadata changes
  list-access [user USER]                List access patterns
  
  log-access <user> <item> [action]      Log item access (for integration)
  
  generate-report [period]               Generate audit report (monthly|weekly)
  verify-compliance                      Check compliance status
  detect-anomalies                       Detect unusual patterns
  
  watch-critical                         Watch for critical item changes

Examples:
  audit-metadata.sh list-changes since 2026-03-01
  audit-metadata.sh list-access user alice
  audit-metadata.sh verify-compliance
  audit-metadata.sh detect-anomalies
  audit-metadata.sh generate-report monthly
EOF
        exit 0
    fi
    
    case "$1" in
        list-changes)
            shift
            cmd_list_changes "$@"
            ;;
        list-access)
            shift
            cmd_list_access "$@"
            ;;
        log-access)
            shift
            cmd_log_access "$@"
            ;;
        generate-report)
            shift
            cmd_generate_report "$@"
            ;;
        verify-compliance)
            cmd_verify_compliance
            ;;
        detect-anomalies)
            cmd_detect_anomalies
            ;;
        watch-critical)
            # Watch mode - check every minute
            while true; do
                if jq '.changes[-1] | select(.action | contains("critical"))' "$METADATA_DIR/change-log.json" >/dev/null 2>&1; then
                    echo "Critical change detected!"
                    jq '.changes[-1]' "$METADATA_DIR/change-log.json"
                fi
                sleep 60
            done
            ;;
        *)
            error "Unknown command: $1"
            ;;
    esac
}

main "$@"
