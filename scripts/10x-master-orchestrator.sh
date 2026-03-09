#!/bin/bash
# 10X IMMUTABLE ACTION LIFECYCLE - MASTER ORCHESTRATOR
# Integrated entry point for the entire auto-fix/auto-repair system
# 
# Usage:
#   ./scripts/10x-master-orchestrator.sh [command] [options]
#
# Commands:
#   discover              List all actions in repo
#   audit                 Generate comprehensive audit report
#   auto-fix              Run complete auto-fix cycle (dry-run by default)
#   auto-fix --force      Run auto-fix with actual repairs
#   rebuild [action]      Rebuild specific action
#   mandate-all           Force rebuild all debugged actions
#   setup                 Initialize system (first-time setup)
#   help                  Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON3=$(command -v python3 || command -v python)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✅${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}❌${NC} $*"
}

log_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$*${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Verify environment
check_prerequisites() {
    local missing=0
    
    if ! command -v "$PYTHON3" &> /dev/null; then
        log_error "Python3 not found"
        missing=1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "Git not found"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        log_error "Missing required tools"
        exit 1
    fi
    
    log_success "Prerequisites verified"
}

# Show help
show_help() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║     10X IMMUTABLE ACTION LIFECYCLE - MASTER ORCHESTRATOR                    ║
╚══════════════════════════════════════════════════════════════════════════════╝

COMMANDS: discover, audit, auto-fix [--force], rebuild [path], mandate-all

Full docs: docs/10X-IMMUTABLE-ACTION-LIFECYCLE.md
EOF
}

# Main entry point
main() {
    check_prerequisites
    
    local command="${1:-help}"
    
    case "$command" in
        discover)
            log_header "🔍 DISCOVERING ACTIONS"
            cd "$REPO_ROOT"
            "$PYTHON3" scripts/immutable-action-lifecycle.py discover
            ;;
        audit)
            log_header "🔐 AUDIT REPORT"
            cd "$REPO_ROOT"
            "$PYTHON3" scripts/immutable-action-lifecycle.py audit --output /tmp/10x-audit-$(date +%s).json
            ;;
        auto-fix)
            cd "$REPO_ROOT"
            "$PYTHON3" scripts/auto-fix-orchestrator.py ${2:+--force}
            ;;
        rebuild)
            [ -n "${2:-}" ] || { log_error "Action path required"; exit 1; }
            cd "$REPO_ROOT"
            "$PYTHON3" scripts/immutable-action-lifecycle.py rebuild --action "$2"
            ;;
        mandate-all)
            log_header "🔶 MANDATE: Rebuild All Debugged Actions"
            cd "$REPO_ROOT"
            "$PYTHON3" scripts/immutable-action-lifecycle.py mandate-all
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
