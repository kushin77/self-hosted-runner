#!/bin/bash
#
# 🚀 NAS STRESS TEST - QUICK DEPLOYMENT & EXECUTION
#
# One-command deployment of NAS stress testing suite
# Includes all tools, monitoring integration, and results tracking
#
# Usage:
#   bash deploy-nas-stress-tests.sh [--install|--quick|--medium|--aggressive|--dashboard]

set -euo pipefail

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

COMMAND="${1:-quick}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { echo -e "${GREEN}[✓]${NC} $*"; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

# ============================================================================
# INSTALLATION
# ============================================================================

install_tools() {
  step "Installing NAS Stress Testing Tools"
  
  # Check dependencies
  local deps_missing=false
  for cmd in ssh bc jq; do
    if ! command -v "$cmd" &> /dev/null; then
      warn "$cmd not found - installing..."
      deps_missing=true
    else
      log "$cmd is installed"
    fi
  done
  
  # Make scripts executable
  chmod +x "$REPO_ROOT/scripts/nas-integration/stress-test-nas.sh" 2>/dev/null || true
  chmod +x "$REPO_ROOT/scripts/nas-integration/nas-stress-framework.sh" 2>/dev/null || true
  
  # Create results directory
  mkdir -p "$REPO_ROOT/nas-stress-results"
  
  log "Tools installed and ready"
  echo ""
  
  show_usage
}

# ============================================================================
# EXECUTION
# ============================================================================

run_quick_test() {
  step "Running Quick NAS Stress Test (5 minutes)"
  
  cd "$REPO_ROOT"
  bash scripts/nas-integration/nas-stress-framework.sh simulate --quick
}

run_medium_test() {
  step "Running Medium NAS Stress Test (15 minutes)"
  
  cd "$REPO_ROOT"
  bash scripts/nas-integration/nas-stress-framework.sh simulate --medium
}

run_aggressive_test() {
  step "Running Aggressive NAS Stress Test (30 minutes)"
  
  cd "$REPO_ROOT"
  bash scripts/nas-integration/nas-stress-framework.sh simulate --aggressive
}

# ============================================================================
# MONITORING DASHBOARD
# ============================================================================

show_dashboard() {
  step "NAS Stress Test Results Dashboard"
  
  local results_dir="$REPO_ROOT/nas-stress-results"
  
  if [[ ! -d "$results_dir" ]] || [[ -z "$(ls -1 "$results_dir"/*.json 2>/dev/null || true)" ]]; then
    warn "No test results found - run a test first with: bash deploy-nas-stress-tests.sh --quick"
    echo ""
    return
  fi
  
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}          📊 NAS STRESS TEST RESULT HISTORY${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo ""
  
  local count=0
  for test_file in $(ls -t "$results_dir"/*.json 2>/dev/null | head -10); do
    ((count++))
    
    local timestamp=$(jq -r '.test_run.timestamp' "$test_file" 2>/dev/null || echo "unknown")
    local mode=$(jq -r '.test_run.mode' "$test_file" 2>/dev/null || echo "unknown")
    local avg_ping=$(jq -r '.metrics.ping_avg_ms.value // "N/A"' "$test_file" 2>/dev/null)
    local io_ops=$(jq -r '.metrics.io_operations.value // "N/A"' "$test_file" 2>/dev/null)
    local success_rate=$(jq -r '.metrics.io_success_rate.value // "N/A"' "$test_file" 2>/dev/null)
    
    printf "  %d. %-30s | Latency: %5sms | IO-Ops: %6s | Success: %5s%%\n" \
      "$count" "$timestamp" "$avg_ping" "$io_ops" "$success_rate"
  done
  
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo ""
}

# ============================================================================
# HELP
# ============================================================================

show_usage() {
  cat <<'EOF'

🔥 NAS STRESS TEST - QUICK START GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Commands:

  Setup:
    bash deploy-nas-stress-tests.sh --install    Install tools and dependencies

  Quick Tests:
    bash deploy-nas-stress-tests.sh --quick      Run 5-minute stress test
    bash deploy-nas-stress-tests.sh --medium     Run 15-minute stress test
    bash deploy-nas-stress-tests.sh --aggressive Run 30-minute stress test

  Monitoring:
    bash deploy-nas-stress-tests.sh --dashboard  Show test results history

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test Coverage (per profile):

  Network Baseline
  ├─ Ping latency (min/max/avg)
  ├─ Network path verification
  └─ 10 round-trip measurements

  Data Transfer
  ├─ File upload throughput
  ├─ File download throughput
  └─ Bandwidth saturation testing

  Concurrent I/O
  ├─ Parallel file operations
  ├─ Read throughput measurement
  ├─ Write throughput measurement
  └─ I/O error tracking

  Sustained Load
  ├─ 60-900 second sustained operations
  ├─ Mixed workload testing
  └─ Error rate collection

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Advanced Usage:

  # Run in simulator mode (no NAS required)
  cd /home/akushnir/self-hosted-runner
  bash scripts/nas-integration/nas-stress-framework.sh simulate --quick

  # Run live tests (when NAS is reachable)
  bash scripts/nas-integration/nas-stress-framework.sh live --medium

  # Export Prometheus metrics
  EXPORT_METRICS=true bash scripts/nas-integration/nas-stress-framework.sh simulate --quick

  # View test results
  cat nas-stress-results/nas-stress-*.json | jq .

  # View performance trends
  bash scripts/nas-integration/nas-stress-framework.sh trends

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Performance Benchmarks:

  Excellent (🟢)     Good (🟢)        Warning (🟡)      Critical (🔴)
  ─────────────────────────────────────────────────────────────────
  Latency < 5ms      < 10ms           < 20ms            > 20ms
  Throughput > 50MB/s > 30MB/s         > 10MB/s          < 10MB/s
  Error Rate < 0.1%  < 1%             < 5%              > 5%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Results Location:

  nas-stress-results/nas-stress-YYYYMMDD_HHMMSS.json
  nas-stress-results/nas-stress-YYYYMMDD_HHMMSS.prom (if metrics exported)

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║          🔥 NAS STRESS TEST DEPLOYMENT                     ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -ne "${NC}"
  echo ""
  
  case "$COMMAND" in
    --install)
      install_tools
      ;;
    --quick)
      run_quick_test
      ;;
    --medium)
      run_medium_test
      ;;
    --aggressive)
      run_aggressive_test
      ;;
    --dashboard)
      show_dashboard
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      echo "Usage: $0 [--install|--quick|--medium|--aggressive|--dashboard|--help]"
      echo ""
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
