#!/bin/bash
#
# 🔥 NAS STRESS TEST SUITE
#
# Comprehensive stress testing for NAS infrastructure (192.168.168.100)
# Tests network performance, I/O throughput, concurrent operations, and reliability
#
# Usage:
#   bash stress-test-nas.sh [--quick|--medium|--aggressive] [--monitor] [--nocleanup]
#
# Defaults:
#   - Runs 'quick' stress profile (5 min total)
#   - Cleans up test files after completion
#   - No real-time monitoring display
#
# Profiles:
#   --quick       ~5 minutes (light testing)
#   --medium      ~15 minutes (moderate load)
#   --aggressive  ~30 minutes (max load and stability testing)

set -euo pipefail

# ============================================================================
# CONFIGURATION & COLORS
# ============================================================================

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# NAS Configuration
readonly NAS_HOST="${NAS_HOST:-192.168.168.39}"
readonly NAS_USER="${NAS_USER:-elevatediq-svc-nas}"
readonly NAS_PORT="${NAS_PORT:-22}"

# Determine NAS key (try multiple paths)
determine_nas_key() {
  local key_candidates=(
    "${NAS_KEY:-default}"
    "$HOME/.ssh/elevatediq-svc-keys/elevatediq-svc-42-nas_key"
    "$HOME/.ssh/elevatediq-svc-keys/elevatediq-svc-worker-nas_key"
    "$HOME/.ssh/elevatediq-svc-keys/elevatediq-svc-dev-nas_key"
    "$HOME/.ssh/id_rsa"
    "$HOME/.ssh/id_ed25519"
  )
  
  for key in "${key_candidates[@]}"; do
    [[ "$key" == "default" ]] && continue
    [[ -f "$key" ]] && echo "$key" && return 0
  done
  
  return 1
}

readonly NAS_KEY="$(determine_nas_key || echo "$HOME/.ssh/id_ed25519")"
readonly NAS_TEST_DIR="/tmp/nas-stress-test-$$"

# Test Configuration
PROFILE="${1:-quick}"
MONITOR_ENABLED="${2:-}"
CLEANUP_ENABLED="${3:-true}"

# Stress Test Parameters
case "$PROFILE" in
  --quick)
    readonly DURATION_SECONDS=300
    readonly FILE_SIZE_MB=100
    readonly CONCURRENT_TRANSFERS=5
    readonly CONCURRENT_READS=10
    readonly FILE_COUNT=50
    ;;
  --medium)
    readonly DURATION_SECONDS=900
    readonly FILE_SIZE_MB=500
    readonly CONCURRENT_TRANSFERS=15
    readonly CONCURRENT_READS=30
    readonly FILE_COUNT=100
    ;;
  --aggressive)
    readonly DURATION_SECONDS=1800
    readonly FILE_SIZE_MB=1000
    readonly CONCURRENT_TRANSFERS=30
    readonly CONCURRENT_READS=50
    readonly FILE_COUNT=200
    ;;
  *)
    echo "Usage: $0 [--quick|--medium|--aggressive] [--monitor] [--nocleanup]"
    exit 1
    ;;
esac

[[ "$MONITOR_ENABLED" == "--monitor" ]] && MONITOR_ENABLED="true" || MONITOR_ENABLED="false"
[[ "$CLEANUP_ENABLED" == "--nocleanup" ]] && CLEANUP_ENABLED="false" || CLEANUP_ENABLED="true"

# Results tracking
declare -A RESULTS=(
  ["ping_min"]=999
  ["ping_max"]=0
  ["ping_avg"]=0
  ["ping_count"]=0
  ["bandwidth_up"]=0
  ["bandwidth_down"]=0
  ["latency_avg"]=0
  ["concurrent_success"]=0
  ["concurrent_failed"]=0
  ["read_throughput"]=0
  ["write_throughput"]=0
  ["errors_total"]=0
)

# ============================================================================
# LOGGING
# ============================================================================

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*"; }

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

nas_command() {
  ssh -i "$NAS_KEY" -p "$NAS_PORT" -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new \
    "${NAS_USER}@${NAS_HOST}" "$@" 2>/dev/null || return 1
}

nas_scp_push() {
  local local_file="$1"
  local remote_path="$2"
  scp -i "$NAS_KEY" -P "$NAS_PORT" -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new \
    "$local_file" "${NAS_USER}@${NAS_HOST}:${remote_path}" 2>/dev/null || return 1
}

nas_scp_pull() {
  local remote_path="$1"
  local local_file="$2"
  scp -i "$NAS_KEY" -P "$NAS_PORT" -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new \
    "${NAS_USER}@${NAS_HOST}:${remote_path}" "$local_file" 2>/dev/null || return 1
}

get_remote_metric() {
  local metric="$1"
  nas_command "cat /proc/stat /proc/meminfo 2>/dev/null | head -5" || echo "0"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

preflight_check() {
  step "Running Pre-Flight Checks"
  
  # Check SSH key exists
  if [[ ! -f "$NAS_KEY" ]]; then
    error "SSH key not found: $NAS_KEY"
    return 1
  fi
  success "SSH key found: $NAS_KEY"
  
  # Check connectivity
  if ! ping -c 1 -W 2 "$NAS_HOST" > /dev/null 2>&1; then
    error "NAS host unreachable: $NAS_HOST"
    return 1
  fi
  success "NAS host reachable: $NAS_HOST"
  
  # Check SSH access
  if ! nas_command "echo 'SSH connectivity OK'" > /dev/null; then
    error "SSH access failed to ${NAS_USER}@${NAS_HOST}:${NAS_PORT}"
    return 1
  fi
  success "SSH access confirmed"
  
  # Create test directory
  if ! nas_command "mkdir -p '$NAS_TEST_DIR' && touch '$NAS_TEST_DIR/.test'" 2>/dev/null; then
    error "Cannot create test directory on NAS"
    return 1
  fi
  success "Test directory created: $NAS_TEST_DIR"
  
  # Verify write permissions
  if ! nas_command "test -w '$NAS_TEST_DIR'"; then
    error "No write permissions to NAS test directory"
    return 1
  fi
  success "Write permissions verified"
  
  echo ""
}

# ============================================================================
# TEST 1: NETWORK BASELINE
# ============================================================================

test_network_baseline() {
  step "TEST 1: Network Baseline (Ping & Latency)"
  
  local ping_times=()
  local total_time=0
  
  for i in {1..10}; do
    local ping_result=$(ping -c 1 -W 1 "$NAS_HOST" 2>/dev/null | grep -oP '\d+\.\d+(?= ms)' | head -1 || echo "999")
    ping_times+=("$ping_result")
    
    local ping_int=${ping_result%.*}
    [[ "$ping_int" -lt ${RESULTS["ping_min"]%.*} ]] && RESULTS["ping_min"]="$ping_int"
    [[ "$ping_int" -gt ${RESULTS["ping_max"]%.*} ]] && RESULTS["ping_max"]="$ping_int"
    total_time=$(echo "$total_time + $ping_result" | bc 2>/dev/null || echo "0")
    ((RESULTS["ping_count"]++))
    
    echo -n "."
  done
  echo ""
  
  RESULTS["ping_avg"]=$(echo "scale=2; $total_time / 10" | bc 2>/dev/null || echo "0")
  
  log "Ping Results:"
  log "  Min: ${RESULTS["ping_min"]}ms"
  log "  Max: ${RESULTS["ping_max"]}ms"
  log "  Avg: ${RESULTS["ping_avg"]}ms"
  echo ""
}

# ============================================================================
# TEST 2: SSH CONNECTION STRESS
# ============================================================================

test_ssh_connections() {
  step "TEST 2: SSH Connection Stress (${CONCURRENT_TRANSFERS} concurrent)"
  
  local success_count=0
  local failed_count=0
  local pids=()
  
  # Start concurrent SSH connections
  for i in $(seq 1 "$CONCURRENT_TRANSFERS"); do
    (
      if nas_command "echo 'Connection $i' > $NAS_TEST_DIR/ssh_test_$i.txt"; then
        ((success_count++))
      else
        ((failed_count++))
      fi
    ) &
    pids+=($!)
  done
  
  # Wait for all background jobs
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || ((failed_count++))
  done
  
  success_count=$(nas_command "ls $NAS_TEST_DIR/ssh_test_*.txt 2>/dev/null | wc -l" || echo "0")
  failed_count=$((CONCURRENT_TRANSFERS - success_count))
  
  RESULTS["concurrent_success"]=$success_count
  RESULTS["concurrent_failed"]=$failed_count
  
  log "SSH Connections: ${success_count}/${CONCURRENT_TRANSFERS} successful"
  [[ $failed_count -gt 0 ]] && warn "Failed connections: $failed_count"
  echo ""
}

# ============================================================================
# TEST 3: FILE UPLOAD THROUGHPUT
# ============================================================================

test_upload_throughput() {
  step "TEST 3: File Upload Throughput"
  
  # Create test file locally
  local test_file="/tmp/nas_upload_test_$$"
  dd if=/dev/zero of="$test_file" bs=1M count="$FILE_SIZE_MB" 2>/dev/null || {
    error "Failed to create test file"
    return 1
  }
  
  log "Test file created: ${FILE_SIZE_MB}MB"
  
  # Measure upload
  local start_time=$(date +%s.%N)
  
  if nas_scp_push "$test_file" "$NAS_TEST_DIR/upload_test_$$.bin"; then
    local end_time=$(date +%s.%N)
    local elapsed=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    local throughput=$(echo "scale=2; ($FILE_SIZE_MB * 1024) / $elapsed" | bc 2>/dev/null || echo "0")
    
    RESULTS["bandwidth_up"]="$throughput"
    success "Upload completed in ${elapsed}s (${throughput} KB/s)"
  else
    error "Upload failed"
    ((RESULTS["errors_total"]++))
  fi
  
  rm -f "$test_file"
  echo ""
}

# ============================================================================
# TEST 4: FILE DOWNLOAD THROUGHPUT
# ============================================================================

test_download_throughput() {
  step "TEST 4: File Download Throughput"
  
  # Create test file on NAS
  nas_command "dd if=/dev/zero of=$NAS_TEST_DIR/download_test_$$.bin bs=1M count=$FILE_SIZE_MB 2>/dev/null" || {
    error "Failed to create NAS test file"
    return 1
  }
  
  log "NAS test file created: ${FILE_SIZE_MB}MB"
  
  # Measure download
  local start_time=$(date +%s.%N)
  local local_file="/tmp/nas_download_test_$$"
  
  if nas_scp_pull "$NAS_TEST_DIR/download_test_$$.bin" "$local_file"; then
    local end_time=$(date +%s.%N)
    local elapsed=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
    local throughput=$(echo "scale=2; ($FILE_SIZE_MB * 1024) / $elapsed" | bc 2>/dev/null || echo "0")
    
    RESULTS["bandwidth_down"]="$throughput"
    success "Download completed in ${elapsed}s (${throughput} KB/s)"
  else
    error "Download failed"
    ((RESULTS["errors_total"]++))
  fi
  
  rm -f "$local_file"
  echo ""
}

# ============================================================================
# TEST 5: CONCURRENT READ/WRITE
# ============================================================================

test_concurrent_io() {
  step "TEST 5: Concurrent Read/Write Operations"
  
  local write_start=$(date +%s.%N)
  local pids=()
  
  # Create multiple test files concurrently
  for i in $(seq 1 "$FILE_COUNT"); do
    (
      nas_command "dd if=/dev/zero of=$NAS_TEST_DIR/file_$i.bin bs=1M count=10" > /dev/null 2>&1
    ) &
    pids+=($!)
    
    # Limit concurrent processes
    if [[ ${#pids[@]} -ge $CONCURRENT_TRANSFERS ]]; then
      wait -n 2>/dev/null || true
    fi
  done
  
  # Wait for all remaining jobs
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  
  local write_end=$(date +%s.%N)
  local write_elapsed=$(echo "$write_end - $write_start" | bc 2>/dev/null || echo "1")
  local write_throughput=$(echo "scale=2; ($FILE_COUNT * 10) / $write_elapsed" | bc 2>/dev/null || echo "0")
  
  RESULTS["write_throughput"]="$write_throughput"
  success "Created $FILE_COUNT files in ${write_elapsed}s (${write_throughput} MB/s)"
  
  # Concurrent reads
  local read_start=$(date +%s.%N)
  pids=()
  
  for i in $(seq 1 "$CONCURRENT_READS"); do
    (
      nas_command "cat $NAS_TEST_DIR/file_$((i % FILE_COUNT + 1)).bin > /dev/null"
    ) &
    pids+=($!)
    
    if [[ ${#pids[@]} -ge $CONCURRENT_READS ]]; then
      wait -n 2>/dev/null || true
    fi
  done
  
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  
  local read_end=$(date +%s.%N)
  local read_elapsed=$(echo "$read_end - $read_start" | bc 2>/dev/null || echo "1")
  local read_throughput=$(echo "scale=2; ($CONCURRENT_READS * 10) / $read_elapsed" | bc 2>/dev/null || echo "0")
  
  RESULTS["read_throughput"]="$read_throughput"
  success "Performed $CONCURRENT_READS concurrent reads in ${read_elapsed}s (${read_throughput} MB/s)"
  echo ""
}

# ============================================================================
# TEST 6: SUSTAINED LOAD TEST
# ============================================================================

test_sustained_load() {
  step "TEST 6: Sustained Load Test (${DURATION_SECONDS}s)"
  
  local start_time=$(date +%s)
  local operations=0
  local operation_errors=0
  
  log "Running sustained operations for ${DURATION_SECONDS} seconds..."
  echo -n "Progress: 0%"
  
  while [[ $(date +%s) -lt $((start_time + DURATION_SECONDS)) ]]; do
    # Rotate through different operations
    for op in {1..5}; do
      case $op in
        1) nas_command "touch $NAS_TEST_DIR/touch_test_$RANDOM" 2>/dev/null && ((operations++)) || ((operation_errors++)) ;;
        2) nas_command "echo 'test' >> $NAS_TEST_DIR/append_test.txt" 2>/dev/null && ((operations++)) || ((operation_errors++)) ;;
        3) nas_command "stat $NAS_TEST_DIR" > /dev/null 2>&1 && ((operations++)) || ((operation_errors++)) ;;
        4) nas_command "ls -la $NAS_TEST_DIR | wc -l" > /dev/null 2>&1 && ((operations++)) || ((operation_errors++)) ;;
        5) nas_command "du -sh $NAS_TEST_DIR" > /dev/null 2>&1 && ((operations++)) || ((operation_errors++)) ;;
      esac
    done
    
    # Show progress every 10%
    local elapsed=$(($(date +%s) - start_time))
    local percent=$((elapsed * 100 / DURATION_SECONDS))
    [[ $((percent % 10)) -eq 0 ]] && echo -ne "\rProgress: ${percent}%"
  done
  
  echo -e "\r                   "
  success "Completed $operations operations in ${DURATION_SECONDS}s"
  [[ $operation_errors -gt 0 ]] && warn "Operation errors: $operation_errors"
  ((RESULTS["errors_total"] += operation_errors))
  echo ""
}

# ============================================================================
# TEST 7: SYSTEM RESOURCE MONITORING
# ============================================================================

test_system_resources() {
  step "TEST 7: System Resource Monitoring"
  
  log "NAS System Metrics (if available):"
  
  # Try to get CPU load
  if cpu_info=$(nas_command "cat /proc/loadavg" 2>/dev/null); then
    log "  Load Average: $cpu_info"
  fi
  
  # Try to get memory info
  if mem_info=$(nas_command "free -h" 2>/dev/null); then
    log "  Memory Info:"
    echo "$mem_info" | sed 's/^/    /'
  fi
  
  # Try to get disk usage
  if disk_info=$(nas_command "df -h $NAS_TEST_DIR" 2>/dev/null); then
    log "  Disk Usage:"
    echo "$disk_info" | sed 's/^/    /'
  fi
  
  # Check test directory size
  if dir_size=$(nas_command "du -sh $NAS_TEST_DIR" 2>/dev/null); then
    log "  Test Directory Size: $dir_size"
  fi
  
  echo ""
}

# ============================================================================
# RESULTS SUMMARY
# ============================================================================

print_results() {
  step "📊 STRESS TEST RESULTS SUMMARY"
  
  echo ""
  echo -e "${CYAN}Network Performance${NC}"
  echo "  Ping Min:       ${RESULTS["ping_min"]}ms"
  echo "  Ping Max:       ${RESULTS["ping_max"]}ms"
  echo "  Ping Avg:       ${RESULTS["ping_avg"]}ms"
  
  echo ""
  echo -e "${CYAN}Connection Performance${NC}"
  echo "  SSH Success:    ${RESULTS["concurrent_success"]}/${CONCURRENT_TRANSFERS}"
  echo "  SSH Failed:     ${RESULTS["concurrent_failed"]}"
  
  echo ""
  echo -e "${CYAN}Data Transfer Throughput${NC}"
  echo "  Upload (KB/s):  ${RESULTS["bandwidth_up"]}"
  echo "  Download (KB/s): ${RESULTS["bandwidth_down"]}"
  
  echo ""
  echo -e "${CYAN}I/O Performance${NC}"
  echo "  Write (MB/s):   ${RESULTS["write_throughput"]}"
  echo "  Read (MB/s):    ${RESULTS["read_throughput"]}"
  
  echo ""
  echo -e "${CYAN}Test Profile${NC}"
  echo "  Duration:       ${DURATION_SECONDS}s"
  echo "  Profile:        $PROFILE"
  echo "  Total Errors:   ${RESULTS["errors_total"]}"
  
  # Health assessment
  echo ""
  echo -e "${CYAN}Health Assessment${NC}"
  local avg_ping=${RESULTS["ping_avg"]%.*}
  local errors=${RESULTS["errors_total"]}
  
  if [[ $avg_ping -lt 5 ]] && [[ $errors -eq 0 ]]; then
    echo -e "${GREEN}  🟢 EXCELLENT - NAS performing optimally${NC}"
  elif [[ $avg_ping -lt 10 ]] && [[ $errors -lt 5 ]]; then
    echo -e "${GREEN}  🟢 GOOD - NAS performance is healthy${NC}"
  elif [[ $avg_ping -lt 20 ]] || [[ $errors -lt 10 ]]; then
    echo -e "${YELLOW}  🟡 WARNING - Consider investigating latency or errors${NC}"
  else
    echo -e "${RED}  🔴 CRITICAL - NAS experiencing performance issues${NC}"
  fi
  
  echo ""
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup() {
  if [[ "$CLEANUP_ENABLED" == "true" ]]; then
    step "Cleaning up test files..."
    if nas_command "rm -rf '$NAS_TEST_DIR'" 2>/dev/null; then
      success "Test directory removed"
    else
      warn "Could not clean up test directory (manual cleanup may be needed)"
    fi
  else
    warn "Cleanup disabled - test files remain at: $NAS_TEST_DIR"
  fi
  echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║         🔥 NAS STRESS TEST SUITE - $(date +%s)         ║"
  echo "║         Target: ${NAS_HOST} (${NAS_USER})                       ║"
  echo "║         Profile: $PROFILE                                    ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -ne "${NC}"
  echo ""
  
  # Run tests
  preflight_check || exit 1
  test_network_baseline
  test_ssh_connections
  test_upload_throughput
  test_download_throughput
  test_concurrent_io
  test_sustained_load
  test_system_resources
  
  # Print results
  print_results
  
  # Cleanup
  cleanup
  
  success "Stress test completed at $(date)"
}

# Safety traps
trap cleanup EXIT
trap 'echo ""; error "Test interrupted"; exit 130' INT TERM

# Execute main
main "$@"
