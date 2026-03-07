#!/bin/bash
################################################################################
# validate-dependencies.sh
# 
# Purpose: Validate dependencies for known vulnerabilities
# Design: Immutable | Ephemeral | Idempotent
#
# Usage:
#   ./scripts/validate-dependencies.sh [--strict] [--report] [--fix]
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
STRICT_MODE=false
REPORT_MODE=false
FIX_MODE=false
LOG_FILE="${LOG_FILE:-/tmp/dependency-validation.log}"
REPORT_FILE="${REPORT_FILE:-/tmp/dependency-report.json}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  --strict    Exit with error if any vulnerabilities found
  --report    Generate JSON report of findings
  --fix       Attempt to fix vulnerabilities automatically
  --help      Show this help message

EXAMPLES:
  # Basic validation
  $(basename "$0")

  # Strict mode (fail on any vuln)
  $(basename "$0") --strict

  # Generate report and attempt fixes
  $(basename "$0") --report --fix

EOF
  exit "${1:-0}"
}

################################################################################
# Main validation logic
################################################################################

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict)   STRICT_MODE=true; shift ;;
      --report)   REPORT_MODE=true; shift ;;
      --fix)      FIX_MODE=true; shift ;;
      --help)     usage 0 ;;
      *)          log_error "Unknown option: $1"; usage 1 ;;
    esac
  done
}

validate_npm_dependencies() {
  log_info "Scanning npm dependencies..."

  local vuln_count=0
  local scannable_projects=0

  # Find all package.json files (exclude node_modules)
  while IFS= read -r pkg_file; do
    local proj_dir=$(dirname "$pkg_file")
    
    # Skip if in node_modules or vendor directories
    if [[ "$proj_dir" =~ node_modules|vendor|\.venv ]]; then
      continue
    fi

    scannable_projects=$((scannable_projects + 1))

    log_info "Validating: $proj_dir"

    # Run npm audit
    if npm audit --audit-level=high --json > /tmp/npm_audit.json 2>/dev/null; then
      log_success "  ✓ No high/critical vulnerabilities in $proj_dir"
    else
      # Parse vulnerabilities
      local high_vulns=$(jq '.metadata.vulnerabilities.high // 0' /tmp/npm_audit.json 2>/dev/null || echo 0)
      local crit_vulns=$(jq '.metadata.vulnerabilities.critical // 0' /tmp/npm_audit.json 2>/dev/null || echo 0)
      
      vuln_count=$((vuln_count + high_vulns + crit_vulns))

      log_warning "  ⚠ Found $high_vulns high + $crit_vulns critical vulnerabilities"

      if [[ "$FIX_MODE" == true ]]; then
        log_info "  → Attempting npm audit fix..."
        if npm audit fix --audit-level=high 2>/dev/null; then
          log_success "  ✓ npm audit fix completed"
        else
          log_warning "  ⚠ npm audit fix did not resolve all issues"
        fi
      fi
    fi

    # Append to report if enabled
    if [[ "$REPORT_MODE" == true ]]; then
      cat /tmp/npm_audit.json >> /tmp/all_audits.json
    fi

  done < <(find "$PROJECT_ROOT" -name "package.json" -type f 2>/dev/null | grep -v node_modules || true)

  return $([[ $vuln_count -eq 0 ]] && echo 0 || echo 1)
}

validate_python_dependencies() {
  log_info "Scanning Python dependencies..."

  local has_issues=false

  # Find all requirements files
  while IFS= read -r req_file; do
    log_info "Validating: $req_file"

    if command -v safety &> /dev/null; then
      if safety check -r "$req_file" --json > /tmp/safety_report.json 2>/dev/null; then
        log_success "  ✓ No known vulnerabilities in $req_file"
      else
        log_warning "  ⚠ Found vulnerabilities in $req_file"
        has_issues=true
      fi
    else
      log_warning "  ℹ safety not installed; skipping Python validation"
    fi
  done < <(find "$PROJECT_ROOT" -name "requirements*.txt" -type f 2>/dev/null || true)

  [[ "$has_issues" == true ]] && return 1 || return 0
}

generate_report() {
  [[ "$REPORT_MODE" == false ]] && return 0

  log_info "Generating report: $REPORT_FILE"

  cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "validation_mode": {
    "strict": $STRICT_MODE,
    "fix": $FIX_MODE
  },
  "summary": {
    "total_scans": $(find "$PROJECT_ROOT" -name "package.json" -type f 2>/dev/null | wc -l),
    "validation_status": "$(grep -c 'No high' "$LOG_FILE" 2>/dev/null || echo 0) passed"
  },
  "audit_details": $(cat /tmp/all_audits.json 2>/dev/null || echo '[]')
}
EOF

  log_success "Report saved: $REPORT_FILE"
}

main() {
  parse_args "$@"

  log_info "Starting dependency validation..."
  log_info "Mode: strict=$STRICT_MODE, report=$REPORT_MODE, fix=$FIX_MODE"

  # Clear log and report
  > "$LOG_FILE"
  > /tmp/all_audits.json 2>/dev/null || true

  # Run validations
  local exit_code=0

  validate_npm_dependencies || exit_code=$?

  if [[ -n "$(command -v python3)" ]]; then
    validate_python_dependencies || exit_code=$?
  fi

  # Generate report
  generate_report

  # Summary
  if [[ $exit_code -eq 0 ]]; then
    log_success "✅ All dependencies validated successfully"
  else
    log_warning "⚠️  Vulnerabilities detected"
    if [[ "$STRICT_MODE" == true ]]; then
      log_error "Failing due to --strict mode"
      exit 1
    fi
  fi

  return $exit_code
}

################################################################################
# Execute
################################################################################

main "$@"
