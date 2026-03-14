#!/bin/bash
# Error Analysis and Centralization Script
# Aggregates and analyzes all errors across the system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ERROR_DIR="${1:-${REPO_ROOT}/logs/errors/central}"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

# Analyze error patterns
analyze_errors() {
  log "Analyzing aggregated errors..."
  
  if [ ! -f "$ERROR_DIR"/*.jsonl ]; then
    log "No error logs found in $ERROR_DIR"
    return 0
  fi
  
  # Extract error types
  local error_types=$(jq -r '.error' "$ERROR_DIR"/*.jsonl 2>/dev/null | sort | uniq -c | sort -rn)
  
  if [ -z "$error_types" ]; then
    log "No structured errors found"
    return 0
  fi
  
  log "Error Type Summary:"
  echo "$error_types" | while read -r count error; do
    log "  $count × $error"
  done
  
  # Find highest-frequency errors
  log "Top recurring errors:"
  echo "$error_types" | head -5 | while read -r count error; do
    log "  [Priority] $count occurrences: $error"
  done
}

# Generate error trends
generate_trends() {
  log "Generating error trend analysis..."
  
  # Group errors by timestamp (hourly)
  log "Errors by hour:"
  jq -r '.timestamp' "$ERROR_DIR"/*.jsonl 2>/dev/null | \
    cut -d'T' -f1,2 | cut -d':' -f1 | uniq -c | \
    while read -r count hour; do
      log "  $count errors in hour $hour"
    done || true
}

# Create actionable recommendations
recommend_actions() {
  log "Generating recommendations..."
  
  local top_error=$(jq -r '.error' "$ERROR_DIR"/*.jsonl 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  
  if [ -n "$top_error" ]; then
    log "Top Error: $top_error"
    log "Recommended Actions:"
    log "  1. Review logs for this error type"
    log "  2. Identify root cause"
    log "  3. Implement fix in affected component"
    log "  4. Deploy fix and validate"
    log "  5. Monitor for recurrence"
  fi
}

main() {
  log "=== Error Analysis Report ==="
  
  mkdir -p "$ERROR_DIR"
  
  if [ ! -d "$ERROR_DIR" ]; then
    log "Error directory not found: $ERROR_DIR"
    return 1
  fi
  
  analyze_errors
  generate_trends
  recommend_actions
  
  log "=== Error Analysis Complete ==="
}

main "$@"
