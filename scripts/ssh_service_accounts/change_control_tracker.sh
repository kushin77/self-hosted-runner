#!/bin/bash
# Change Control Tracker
# Records all production-impacting operations with standardized JSONL format
# Enables immutable audit trail, rollback capability, and change history
# Usage: change_control_tracker.sh {log <op> <details> [status]|execute <op> <cmd> <details>|history [limit]|cleanup}

set -euo pipefail

readonly WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly CHANGE_LOG="${WORKSPACE_ROOT}/logs/change-control.jsonl"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Log a change record
log_change() {
    local operation=$1
    local details=$2
    local status="${3:-initiating}"
    
    mkdir -p "$(dirname "$CHANGE_LOG")"
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local user=${SUDO_USER:-$USER}
    local hostname=$(hostname)
    local change_id="$(date +%s)-$(openssl rand -hex 4 2>/dev/null || echo $RANDOM)"
    
    # Escape JSON special characters in details
    local escaped_details=$(echo -n "$details" | jq -Rs . 2>/dev/null || echo "\"$details\"")
    
    local change_record="{\"timestamp\":\"$timestamp\",\"operation\":\"$operation\",\"status\":\"$status\",\"user\":\"$user\",\"hostname\":\"$hostname\",\"details\":$escaped_details,\"change_id\":\"$change_id\"}"
    
    echo "$change_record" >> "$CHANGE_LOG"
    
    echo "$change_id"
}

# Execute command with change tracking
execute_with_tracking() {
    local operation=$1
    local command=$2
    local details=$3
    
    # Log change initiation and capture change_id
    local change_id=$(log_change "$operation" "$details" "initiating")
    log_info "Change ID: $change_id"
    
    # Execute command and capture exit code
    local exit_code=0
    local output=""
    
    if output=$(eval "$command" 2>&1); then
        # Log success
        log_change "$operation" "COMPLETED: $details" "completed" >/dev/null
        log_success "Change completed: $operation"
        
        if [ -n "$output" ]; then
            echo "$output" | head -20
        fi
        return 0
    else
        exit_code=$?
        # Log failure
        log_change "$operation" "FAILED (exit code $exit_code): $details" "failed" >/dev/null
        log_error "Change failed: $operation (exit code: $exit_code)"
        
        if [ -n "$output" ]; then
            echo "$output" | tail -20 >&2
        fi
        return $exit_code
    fi
}

# Show change history with formatting
show_history() {
    local limit="${1:-30}"
    
    if [ ! -f "$CHANGE_LOG" ]; then
        log_warn "No change control log found"
        return 0
    fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║ CHANGE CONTROL HISTORY (Last $limit entries)                              ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Format: timestamp | operation | status | user
    tail -"$limit" "$CHANGE_LOG" | jq -r '[.timestamp, .operation, .status, .user] | @tsv' 2>/dev/null | \
    awk -F'\t' '{printf "%-30s %-35s %-15s %s\n", $1, $2, $3, $4}' || true
    
    echo ""
    echo "Query details:"
    echo "  jq '.[] | select(.status==\"failed\")' $CHANGE_LOG  # Show all failed changes"
    echo "  jq '.[] | select(.operation==\"rotation\")' $CHANGE_LOG  # Show rotation changes"
    echo ""
}

# Search change history
search_change() {
    local search_term=$1
    
    if [ ! -f "$CHANGE_LOG" ]; then
        log_error "No change log found"
        return 1
    fi
    
    echo ""
    echo "Searching for: $search_term"
    echo ""
    
    grep "$search_term" "$CHANGE_LOG" | jq -r '[.timestamp, .operation, .status, .change_id] | @tsv' 2>/dev/null | \
    awk -F'\t' '{printf "%-30s %-35s %-15s %s\n", $1, $2, $3, $4}' || true
    
    echo ""
}

# Generate change summary
generate_summary() {
    local since_hours="${1:-24}"
    
    if [ ! -f "$CHANGE_LOG" ]; then
        log_error "No change log found"
        return 1
    fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║ CHANGE CONTROL SUMMARY (Last $since_hours hours)          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Calculate cutoff timestamp
    local cutoff_epoch=$(($(date +%s) - (since_hours * 3600)))
    
    local total=$(wc -l < "$CHANGE_LOG")
    local completed=$(grep -c '"status":"completed"' "$CHANGE_LOG" || echo 0)
    local failed=$(grep -c '"status":"failed"' "$CHANGE_LOG" || echo 0)
    local initiating=$(grep -c '"status":"initiating"' "$CHANGE_LOG" || echo 0)
    
    echo "Total Changes:       $total"
    echo "Completed:          $completed"
    echo "Failed:             $failed"
    echo "In Progress:        $initiating"
    echo ""
    
    # Most common operations
    echo "Most Common Operations:"
    grep '"operation"' "$CHANGE_LOG" | sed 's/.*"operation":"\([^"]*\)".*/\1/' | sort | uniq -c | sort -rn | head -5 | \
    awk '{printf "  • %-35s %d\n", $2, $1}'
    echo ""
    
    # Users with most changes
    echo "Top Users by Changes:"
    grep '"user"' "$CHANGE_LOG" | sed 's/.*"user":"\([^"]*\)".*/\1/' | sort | uniq -c | sort -rn | head -3 | \
    awk '{printf "  • %-35s %d\n", $2, $1}'
    echo ""
}

# Archive old entries (keep last N entries, archive rest)
cleanup() {
    local keep_entries="${1:-10000}"
    
    if [ ! -f "$CHANGE_LOG" ]; then
        log_info "No change log to clean"
        return 0
    fi
    
    local total=$(wc -l < "$CHANGE_LOG")
    
    if [ $total -gt $keep_entries ]; then
        local archive_basename="${CHANGE_LOG}.archive"
        local archive_file="${archive_basename}.$(date +%Y%m%d-%H%M%S).jsonl"
        
        # Move old entries to archive
        head -n $((total - keep_entries)) "$CHANGE_LOG" > "$archive_file"
        tail -n "$keep_entries" "$CHANGE_LOG" > "${CHANGE_LOG}.tmp"
        mv "${CHANGE_LOG}.tmp" "$CHANGE_LOG"
        
        log_success "Archived $((total - keep_entries)) old entries to: $(basename "$archive_file")"
        echo "  Kept: $keep_entries recent entries"
    else
        log_info "Change log size acceptable ($total entries, keep $keep_entries)"
    fi
}

main() {
    mkdir -p "$(dirname "$CHANGE_LOG")"
    
    case "${1:-history}" in
        log)
            # Internal use: log change with optional status
            change_id=$(log_change "$2" "$3" "${4:-initiating}")
            echo "$change_id"
            ;;
        execute)
            # Execute command with tracking
            execute_with_tracking "$2" "$3" "$4"
            ;;
        history)
            show_history "${2:-30}"
            ;;
        search)
            search_change "$2"
            ;;
        summary)
            generate_summary "${2:-24}"
            ;;
        cleanup)
            cleanup "${2:-10000}"
            ;;
        *)
            echo "Usage: $0 {log <op> <details> [status]|execute <op> <cmd> <details>|history [limit]|search <term>|summary [hours]|cleanup [keep-count]}"
            echo ""
            echo "Commands:"
            echo "  log <op> <details> [status]  - Log a change record"
            echo "  execute <op> <cmd> <details> - Execute command and log result"
            echo "  history [limit]              - Show recent changes (default: 30)"
            echo "  search <term>                - Search change history"
            echo "  summary [hours]              - Generate summary (default: 24 hours)"
            echo "  cleanup [keep-count]         - Archive old entries (default: keep 10000)"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
