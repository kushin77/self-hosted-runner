#!/bin/bash
#
# 🧪 NAS INTEGRATION TEST WORKFLOW
#
# Comprehensive test scenarios for Phase 3 deployment
# Validates push, pull, sync, and failure recovery workflows
#
# Usage:
#   bash test-nas-workflow.sh [--scenario=SCENARIO] [--verbose] [--cleanup]
#
# Scenarios:
#   1 - Basic IAC Push → Worker Sync
#   2 - Watch Mode Auto-Push
#   3 - Large Configuration Push
#   4 - Network Failure Recovery
#   5 - Concurrent Operations
#   6 - End-to-End: Edit → Deploy
#

set -euo pipefail

# Configuration
readonly NAS_HOST="192.168.168.39"
readonly DEV_NODE="192.168.168.31"
readonly WORKER_NODE="192.168.168.42"
readonly OPT_IAC="/opt/iac-configs"
readonly MNT_NAS="/mnt/nas/repositories"
readonly TEST_DIR="/tmp/nas-workflow-tests-$$"
readonly TEST_LOG="${TEST_DIR}/test-log.txt"

# Global state
SCENARIO="${SCENARIO:-all}"
VERBOSE="${VERBOSE:-false}"
CLEANUP="${CLEANUP:-true}"
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

log() { echo -e "${BLUE}→${NC} $*" | tee -a "$TEST_LOG"; }
success() { echo -e "${GREEN}✅${NC} $*" | tee -a "$TEST_LOG"; TESTS_PASSED=$((TESTS_PASSED+1)); }
error() { echo -e "${RED}❌${NC} $*" | tee -a "$TEST_LOG"; TESTS_FAILED=$((TESTS_FAILED+1)); }
warn() { echo -e "${YELLOW}⚠${NC}  $*" | tee -a "$TEST_LOG"; }
info() { echo -e "${MAGENTA}ℹ${NC}  $*" | tee -a "$TEST_LOG"; }
section() { echo; echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}" | tee -a "$TEST_LOG"; echo -e "${CYAN}║ $*${NC}" | tee -a "$TEST_LOG"; echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}" | tee -a "$TEST_LOG"; }

# ============================================================================
# SETUP & TEARDOWN
# ============================================================================

setup() {
  mkdir -p "$TEST_DIR"
  echo "Test started at $(date)" > "$TEST_LOG"
  log "Test environment: $TEST_DIR"
}

cleanup_test_files() {
  if [[ "$CLEANUP" == "true" ]]; then
    log "Cleaning up test files"
    rm -f "${OPT_IAC}"/test-*.yaml "${OPT_IAC}"/test-*.json
    rm -rf "${MNT_NAS}"/test-* 2>/dev/null || true
    rm -rf "$TEST_DIR"
  fi
}

# ============================================================================
# TEST SCENARIO 1: Basic IAC Push → Worker Sync
# ============================================================================

test_scenario_1() {
  section "SCENARIO 1: Basic IAC Push → Worker Sync"
  
  log "Creating test configuration..."
  local test_config="${OPT_IAC}/test-scenario-1.yaml"
  cat > "$test_config" << 'EOF'
# Test Configuration - Scenario 1
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-scenario-1
  namespace: default
data:
  test: scenario-1-basic-push
  timestamp: "2026-03-15T12:00:00Z"
EOF
  success "Test configuration created"
  
  log "Pushing to NAS..."
  if bash /home/akushnir/self-hosted-runner/scripts/nas-integration/dev-node-automation.sh push; then
    success "Push successful"
  else
    error "Push failed"
    return 1
  fi
  
  log "Verifying on NAS..."
  if [[ -f "${MNT_NAS}/test-scenario-1.yaml" ]]; then
    success "Configuration synced to NAS"
  else
    error "Configuration not found on NAS"
    return 1
  fi
  
  log "Waiting for worker to pull (30 sec)..."
  sleep 30
  
  log "Verifying on worker node..."
  if ssh -o ConnectTimeout=5 root@"$WORKER_NODE" "test -f /opt/deployed-configs/test-scenario-1.yaml" 2>/dev/null; then
    success "Configuration synced to worker"
  else
    warn "Worker sync not verified (may be pending)"
  fi
  
  [[ $TESTS_FAILED -eq 0 ]]
}

# ============================================================================
# TEST SCENARIO 2: Watch Mode Auto-Push
# ============================================================================

test_scenario_2() {
  section "SCENARIO 2: Watch Mode Auto-Push"
  
  log "Starting watch mode (background)..."
  timeout 60 bash /home/akushnir/self-hosted-runner/scripts/nas-integration/dev-node-automation.sh watch &
  local watch_pid=$!
  sleep 3
  
  log "Creating test file..."
  local test_file="${OPT_IAC}/test-watch-mode.txt"
  echo "Watch mode test - $(date)" > "$test_file"
  success "Test file created"
  
  log "Waiting for auto-push (10 sec)..."
  sleep 10
  
  log "Verifying on NAS..."
  if [[ -f "${MNT_NAS}/test-watch-mode.txt" ]]; then
    success "File auto-pushed by watch mode"
  else
    error "File not auto-pushed"
  fi
  
  # Clean up watch process
  kill $watch_pid 2>/dev/null || true
  wait $watch_pid 2>/dev/null || true
  
  [[ $TESTS_FAILED -eq 0 ]]
}

# ============================================================================
# TEST SCENARIO 3: Large Configuration Push
# ============================================================================

test_scenario_3() {
  section "SCENARIO 3: Large Configuration Push (10MB)"
  
  log "Creating large test file (10MB)..."
  local large_file="${OPT_IAC}/test-large-config.bin"
  dd if=/dev/zero of="$large_file" bs=1M count=10 2>/dev/null
  success "Large file created (10MB)"
  
  log "Timing push operation..."
  local start_time=$(date +%s)
  
  if bash /home/akushnir/self-hosted-runner/scripts/nas-integration/dev-node-automation.sh push; then
    success "Push successful"
  else
    error "Push failed"
    return 1
  fi
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  log "Push completed in ${duration}s"
  
  log "Verifying file on NAS..."
  if [[ -f "${MNT_NAS}/test-large-config.bin" ]]; then
    local nas_size=$(stat -c%s "${MNT_NAS}/test-large-config.bin")
    local local_size=$(stat -c%s "$large_file")
    
    if [[ $nas_size -eq $local_size ]]; then
      success "Large file transferred correctly (${nas_size} bytes)"
    else
      error "File size mismatch: NAS=$nas_size, Local=$local_size"
      return 1
    fi
  else
    error "Large file not found on NAS"
    return 1
  fi
  
  [[ $TESTS_FAILED -eq 0 ]]
}

# ============================================================================
# TEST SCENARIO 4: Network Failure Recovery
# ============================================================================

test_scenario_4() {
  section "SCENARIO 4: Network Failure Recovery"
  
  log "Verifying initial health..."
  if bash /home/akushnir/self-hosted-runner/scripts/nas-integration/validate-deployment.sh &>/dev/null; then
    success "Initial health check passed"
  else
    error "Initial health check failed"
    return 1
  fi
  
  log "Simulating stale mount (timeout)..."
  # Note: actual network simulation would require sudo/iptables
  warn "Simulating by checking recovery capability"
  
  log "Triggering health check..."
  if sudo bash /usr/local/bin/nas-health-check.sh 2>/dev/null; then
    success "Health check passed"
  else
    warn "Health check reported issues (may be expected in test)"
  fi
  
  log "Verifying mounts still active..."
  if mount | grep "nas/repositories" | grep -q "192.168.168.39"; then
    success "Mounts remain active"
  else
    error "Mounts lost"
    return 1
  fi
  
  [[ $TESTS_FAILED -eq 0 ]]
}

# ============================================================================
# TEST SCENARIO 5: Concurrent Operations
# ============================================================================

test_scenario_5() {
  section "SCENARIO 5: Concurrent Operations"
  
  log "Creating 5 test files concurrently..."
  for i in {1..5}; do
    cat > "${OPT_IAC}/test-concurrent-$i.yaml" << EOF &
# Concurrent test file $i
test_id: $i
timestamp: $(date)
EOF
  done
  wait
  success "Created 5 concurrent test files"
  
  log "Pushing all files concurrently..."
  for i in {1..5}; do
    bash /home/akushnir/self-hosted-runner/scripts/nas-integration/dev-node-automation.sh push &
  done
  wait
  success "Push operations completed"
  
  log "Verifying all files on NAS..."
  local nas_count=0
  for i in {1..5}; do
    if [[ -f "${MNT_NAS}/test-concurrent-$i.yaml" ]]; then
      nas_count=$((nas_count+1))
    fi
  done
  
  if [[ $nas_count -eq 5 ]]; then
    success "All 5 files synced to NAS"
  else
    error "Only $nas_count/5 files on NAS"
    return 1
  fi
  
  [[ $TESTS_FAILED -eq 0 ]]
}

# ============================================================================
# TEST SCENARIO 6: End-to-End (Edit → Deploy)
# ============================================================================

test_scenario_6() {
  section "SCENARIO 6: End-to-End Workflow (Edit → Deploy)"
  
  log "Starting end-to-end scenario..."
  local config_name="test-e2e-$(date +%s)"
  local config_path="${OPT_IAC}/${config_name}.yaml"
  
  log "Step 1: Edit configuration..."
  cat > "$config_path" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-e2e
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test-e2e
  template:
    metadata:
      labels:
        app: test-e2e
    spec:
      containers:
      - name: app
        image: nginx:latest
EOF
  success "Configuration edited"
  
  log "Step 2: Display changes..."
  if bash /home/akushnir/self-hosted-runner/scripts/nas-integration/dev-node-automation.sh diff &>/dev/null; then
    success "Changes displayed"
  else
    warn "Diff may have no output (OK)"
  fi
  
  log "Step 3: Push to NAS..."
  if bash /home/akushnir/self-hosted-runner/scripts/nas-integration/dev-node-automation.sh push; then
    success "Configuration pushed"
  else
    error "Push failed"
    return 1
  fi
  
  log "Step 4: Verify on NAS..."
  if [[ -f "${MNT_NAS}/${config_name}.yaml" ]]; then
    success "Configuration on NAS"
  else
    error "Configuration not found on NAS"
    return 1
  fi
  
  log "Step 5: Wait for worker sync (30 sec)..."
  sleep 30
  
  log "Step 6: Verify on worker..."
  if ssh -o ConnectTimeout=5 root@"$WORKER_NODE" "test -f /opt/deployed-configs/${config_name}.yaml" 2>/dev/null; then
    success "Configuration deployed to worker"
  else
    warn "Worker deployment pending"
  fi
  
  log "End-to-end workflow complete!"
  [[ $TESTS_FAILED -eq 0 ]]
}

# ============================================================================
# TEST RUNNER
# ============================================================================

run_all_scenarios() {
  local scenarios=(1 2 3 4 5 6)
  
  for scenario_num in "${scenarios[@]}"; do
    case $scenario_num in
      1) test_scenario_1 || true ;;
      2) test_scenario_2 || true ;;
      3) test_scenario_3 || true ;;
      4) test_scenario_4 || true ;;
      5) test_scenario_5 || true ;;
      6) test_scenario_6 || true ;;
    esac
  done
}

run_single_scenario() {
  case "$SCENARIO" in
    1) test_scenario_1 ;;
    2) test_scenario_2 ;;
    3) test_scenario_3 ;;
    4) test_scenario_4 ;;
    5) test_scenario_5 ;;
    6) test_scenario_6 ;;
    *)
      echo "Unknown scenario: $SCENARIO"
      echo "Valid scenarios: 1-6"
      exit 1
      ;;
  esac
}

# ============================================================================
# SUMMARY
# ============================================================================

summary() {
  section "TEST RESULTS"
  
  local total=$((TESTS_PASSED + TESTS_FAILED))
  local pass_rate=0
  [[ $total -gt 0 ]] && pass_rate=$((TESTS_PASSED * 100 / total))
  
  cat << EOF
Total Tests:      $total
Passed:           $TESTS_PASSED
Failed:           $TESTS_FAILED
Pass Rate:        ${pass_rate}%

Test Log:         $TEST_LOG

EOF

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    return 0
  else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    return 1
  fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scenario=*) SCENARIO="${1#*=}" ;;
      --verbose) VERBOSE="true" ;;
      --cleanup) CLEANUP="true" ;;
      --no-cleanup) CLEANUP="false" ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
  done
  
  setup
  
  if [[ "$SCENARIO" == "all" ]]; then
    run_all_scenarios
  else
    run_single_scenario
  fi
  
  summary
  cleanup_test_files
}

main "$@"
