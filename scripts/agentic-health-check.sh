#!/bin/bash
# Health check for agentic workflow infrastructure
# Validates Ollama availability, runner status, and model readiness

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"
LOG_FILE="/var/log/agentic-health-check.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  local level="$1"
  shift
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "[${timestamp}] [${level}] $*" | tee -a "$LOG_FILE"
}

check_ollama_running() {
  log "INFO" "Checking Ollama service..."
  
  if systemctl is-active --quiet ollama; then
    log "OK" "✅ Ollama service is running"
    return 0
  else
    log "WARN" "⚠️  Ollama service is not running"
    log "INFO" "Attempting to start Ollama..."
    systemctl start ollama || {
      log "ERROR" "❌ Failed to start Ollama service"
      return 1
    }
    sleep 2
    return 0
  fi
}

check_ollama_health() {
  log "INFO" "Checking Ollama API health..."
  
  if curl -sf --connect-timeout "$HEALTH_CHECK_TIMEOUT" \
    "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
    log "OK" "✅ Ollama API responding"
    return 0
  else
    log "ERROR" "❌ Ollama API not responding at $OLLAMA_URL"
    return 1
  fi
}

check_models_available() {
  log "INFO" "Checking available models..."
  
  local response
  response=$(curl -sf --connect-timeout "$HEALTH_CHECK_TIMEOUT" \
    "$OLLAMA_URL/api/tags" 2>/dev/null || echo '{}')
  
  local model_count
  model_count=$(echo "$response" | grep -o '"models"' | wc -l)
  
  if [ "$model_count" -gt 0 ]; then
    log "OK" "✅ Models available"
    echo "$response" | python3 -m json.tool 2>/dev/null | grep '"name"' | head -3 | while read -r line; do
      log "INFO" "  $line"
    done || true
    return 0
  else
    log "WARN" "⚠️  No models currently loaded (will download on first use)"
    return 0
  fi
}

check_runner_status() {
  log "INFO" "Checking GitHub Actions runner status..."
  
  if systemctl is-active --quiet github-actions-runner; then
    log "OK" "✅ GitHub Actions runner is running"
    return 0
  else
    log "ERROR" "❌ GitHub Actions runner is not running"
    return 1
  fi
}

check_workflow_dir() {
  log "INFO" "Checking agentic workflows directory..."
  
  if [ -d ".github/workflows/agentic" ]; then
    local count
    count=$(find .github/workflows/agentic -name "*.lock.yml" 2>/dev/null | wc -l)
    log "OK" "✅ Found $count compiled workflows"
    return 0
  else
    log "WARN" "⚠️  Workflows directory not found (.github/workflows/agentic)"
    return 0
  fi
}

export_metrics() {
  log "INFO" "Exporting health metrics to Prometheus format..."
  
  local metrics_file="/tmp/agentic_health_metrics.txt"
  
  {
    echo "# HELP agentic_ollama_service Ollama service running (1=yes, 0=no)"
    echo "# TYPE agentic_ollama_service gauge"
    if systemctl is-active --quiet ollama; then
      echo "agentic_ollama_service 1"
    else
      echo "agentic_ollama_service 0"
    fi
    
    echo "# HELP agentic_ollama_api_health Ollama API responding (1=yes, 0=no)"
    echo "# TYPE agentic_ollama_api_health gauge"
    if curl -sf --connect-timeout "$HEALTH_CHECK_TIMEOUT" \
      "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
      echo "agentic_ollama_api_health 1"
    else
      echo "agentic_ollama_api_health 0"
    fi
    
    echo "# HELP agentic_runner_status GitHub Actions runner running (1=yes, 0=no)"
    echo "# TYPE agentic_runner_status gauge"
    if systemctl is-active --quiet github-actions-runner; then
      echo "agentic_runner_status 1"
    else
      echo "agentic_runner_status 0"
    fi
  } > "$metrics_file"
  
  log "OK" "✅ Metrics exported to $metrics_file"
}

run_full_check() {
  log "INFO" "======================================="
  log "INFO" "Agentic Workflows Health Check"
  log "INFO" "======================================="
  log "INFO" "Hostname: $(hostname)"
  log "INFO" "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  
  local status=0
  
  check_ollama_running || status=1
  check_ollama_health || status=1
  check_models_available || true  # Non-critical
  check_runner_status || status=1
  check_workflow_dir || true      # Non-critical
  
  log "INFO" "======================================="
  
  if [ $status -eq 0 ]; then
    log "OK" "✅ All critical checks passed"
  else
    log "ERROR" "❌ Some checks failed - review logs above"
  fi
  
  export_metrics
  
  return $status
}

main() {
  mkdir -p "$(dirname "$LOG_FILE")"
  
  case "${1:-check}" in
    check)
      run_full_check
      ;;
    quick)
      check_ollama_health && check_runner_status
      ;;
    metrics)
      export_metrics
      ;;
    logs)
      tail -20 "$LOG_FILE"
      ;;
    *)
      echo "Usage: $0 {check|quick|metrics|logs}"
      exit 1
      ;;
  esac
}

main "$@"
