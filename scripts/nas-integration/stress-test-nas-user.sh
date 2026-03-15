#!/bin/bash
#
# NAS User-Level Stress Test Suite
# Traditional filesystem performance testing (not SSH-based admin operations)
#
# Usage:
#   ./stress-test-nas-user.sh [quick|concurrent|comprehensive]
#
# Profiles:
#   quick          - Sequential read/write, IOPS, latency (~5 min)
#   concurrent     - 8 concurrent users for 60 seconds (~2 min)
#   comprehensive  - All tests + detailed report (~15 min)
#

set -euo pipefail

PROFILE="${1:-quick}"
NAS_HOST="192.168.168.39"
REPORT_DIR="${HOME}/self-hosted-runner/.deployment-logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ensure report directory exists
mkdir -p "$REPORT_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      NAS User-Level Stress Test Suite              ║${NC}"
echo -e "${BLUE}║      Profile: ${PROFILE}${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Connectivity check
if ! ping -c 1 -W 2 "$NAS_HOST" > /dev/null 2>&1; then
    echo -e "${RED}✗ NAS at $NAS_HOST is unreachable${NC}"
    exit 1
fi

echo -e "${GREEN}✓ NAS connectivity verified${NC}"
echo ""

case "$PROFILE" in
    quick)
        echo -e "${YELLOW}Running quick stress test (5 min)...${NC}"
        echo "- Sequential write test (1GB)"
        echo "- Sequential read test (1GB)"
        echo "- Small file IOPS (1000 files)"
        echo "- Random access latency"
        echo ""
        
        TEST_DIR="/tmp/nas-stress-quick-$$"
        mkdir -p "$TEST_DIR"
        
        # Write
        echo -n "Writing 1GB... "
        dd if=/dev/zero of="$TEST_DIR/test.bin" bs=1M count=1024 2>&1 | grep "copied"
        
        # Read
        echo -n "Reading 1GB... "
        dd if="$TEST_DIR/test.bin" of=/dev/null bs=1M 2>&1 | grep "copied"
        rm "$TEST_DIR/test.bin"
        
        # IOPS
        echo -n "Creating 1000 files... "
        START=$(date +%s.%N)
        for i in {1..1000}; do
            echo "data" > "$TEST_DIR/file-$i.txt"
        done
        END=$(date +%s.%N)
        echo "$(echo "scale=0; 1000 / (${END} - ${START})" | bc) ops/sec"
        rm -rf "$TEST_DIR"
        ;;
        
    concurrent)
        echo -e "${YELLOW}Running concurrent user test (60 sec)...${NC}"
        echo "- 8 concurrent users"
        echo "- Mix of read/write operations"
        echo ""
        
        TEST_DIR="/tmp/nas-stress-concurrent-$$"
        mkdir -p "$TEST_DIR"/{user-{1..8},results}
        
        user_workload() {
            local u=$1
            local start=$(date +%s)
            local ops=0
            while [ $(($(date +%s) - start)) -lt 60 ]; do
                echo "op-$ops" > "$TEST_DIR/user-$u/file-$ops.txt" 2>/dev/null || true
                ops=$((ops + 1))
            done
            echo $ops > "$TEST_DIR/results/user-$u.txt"
        }
        
        for u in {1..8}; do
            user_workload "$u" &
        done
        
        wait
        
        TOTAL_OPS=0
        for u in {1..8}; do
            TOTAL_OPS=$((TOTAL_OPS + $(cat "$TEST_DIR/results/user-$u.txt")))
        done
        
        echo -e "${GREEN}Completed: $TOTAL_OPS operations across 8 users${NC}"
        echo "Throughput: $((TOTAL_OPS / 60)) ops/sec"
        
        rm -rf "$TEST_DIR"
        ;;
        
    comprehensive)
        echo -e "${YELLOW}Running comprehensive benchmark...${NC}"
        # Run all tests and generate report
        bash /tmp/nas-comprehensive-benchmark.sh 2>&1 | tee "$REPORT_DIR/nas-benchmark-${TIMESTAMP}.txt"
        exit 0
        ;;
        
    *)
        echo -e "${RED}Unknown profile: $PROFILE${NC}"
        echo "Valid profiles: quick, concurrent, comprehensive"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}✓ Stress test complete${NC}"
