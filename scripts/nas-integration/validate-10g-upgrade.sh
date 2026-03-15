#!/bin/bash
set -euo pipefail

# validate-10g-upgrade.sh
# Runs a set of pre-upgrade validation checks for 10G migration:
# - Verifies NFS mount
# - Runs iperf3 network test (if iperf3 available and server running)
# - Runs fio (if available) for sequential and random tests on the NFS mount
# - Runs small-file IOPS and latency checks
# Results saved to .deployment-logs/nas-10g-validation-*.log

LOGDIR="$(pwd)/.deployment-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/nas-10g-validation-$(date +%Y%m%d-%H%M%S).log"
NAS_HOST="192.168.168.39"
MOUNT_POINT="/mnt/nas/repositories"

echo "=== 10G VALIDATION - $(date)" | tee "$LOGFILE"

# 1) Verify NFS mount
if mountpoint -q "$MOUNT_POINT"; then
  echo "[OK] NFS mount found at $MOUNT_POINT" | tee -a "$LOGFILE"
else
  echo "[ERROR] No NFS mount at $MOUNT_POINT. Mount before running tests." | tee -a "$LOGFILE"
  echo "Run: sudo mkdir -p $MOUNT_POINT && sudo mount -t nfs4 -o vers=4.1,proto=tcp,hard,timeo=30,retrans=3  $NAS_HOST:/export/repositories $MOUNT_POINT" | tee -a "$LOGFILE"
  exit 2
fi

# 2) iperf3 test (network raw link)
if command -v iperf3 >/dev/null 2>&1; then
  echo "[INFO] iperf3 found. Attempting iperf3 client -> $NAS_HOST (30s, 4 streams)" | tee -a "$LOGFILE"
  if iperf3 -c "$NAS_HOST" -P 4 -t 15 > "$LOGDIR/iperf3-client.out" 2>&1; then
    echo "[OK] iperf3 client completed. Output saved to $LOGDIR/iperf3-client.out" | tee -a "$LOGFILE"
    tail -n 20 "$LOGDIR/iperf3-client.out" | tee -a "$LOGFILE"
  else
    echo "[WARN] iperf3 client failed or server not running on $NAS_HOST. Check iperf3 server on NAS." | tee -a "$LOGFILE"
  fi
else
  echo "[WARN] iperf3 not installed. Install with: sudo apt-get install -y iperf3" | tee -a "$LOGFILE"
fi

# 3) Quick sequential write/read with fio or dd
TEST_DIR="$MOUNT_POINT/.validation-$$"
mkdir -p "$TEST_DIR"

if command -v fio >/dev/null 2>&1; then
  echo "[INFO] fio found. Running sequential and random tests (1G)." | tee -a "$LOGFILE"
  fio --name=seqwrite --filename=$TEST_DIR/fio-seq --rw=write --bs=1M --size=1G --direct=1 --numjobs=1 --iodepth=32 --runtime=30 --time_based=0 --output="$LOGDIR/fio-seq.out"
  fio --name=seqread --filename=$TEST_DIR/fio-seq --rw=read --bs=1M --size=1G --direct=1 --numjobs=1 --iodepth=32 --runtime=30 --time_based=0 --output="$LOGDIR/fio-seq-read.out"
  fio --name=rand --filename=$TEST_DIR/fio-rand --rw=randrw --bs=4k --rwmixread=70 --size=1G --direct=1 --numjobs=8 --iodepth=64 --runtime=30 --time_based=0 --output="$LOGDIR/fio-rand.out"
  echo "[OK] fio tests complete; outputs: $LOGDIR/fio-*.out" | tee -a "$LOGFILE"
else
  echo "[INFO] fio not found. Falling back to dd for sequential check." | tee -a "$LOGFILE"
  echo "Writing 1GB via dd (sync) to $TEST_DIR/test-1g.bin" | tee -a "$LOGFILE"
  dd if=/dev/zero of="$TEST_DIR/test-1g.bin" bs=1M count=1024 oflag=direct 2>&1 | tee -a "$LOGFILE"
  echo "Reading 1GB via dd from $TEST_DIR/test-1g.bin" | tee -a "$LOGFILE"
  dd if="$TEST_DIR/test-1g.bin" of=/dev/null bs=1M 2>&1 | tee -a "$LOGFILE"
fi

# 4) Small file IOPS test
echo "[INFO] Running small-file IOPS test (1000 files)" | tee -a "$LOGFILE"
START=$(date +%s.%N)
for i in $(seq 1 1000); do
  printf "x\n" > "$TEST_DIR/file-$i.txt"
done
END=$(date +%s.%N)
ELAPSED=$(echo "$END - $START" | bc)
IOPS=$(echo "scale=2; 1000 / $ELAPSED" | bc)
echo "Small-file create: $IOPS ops/sec ($ELAPSED s)" | tee -a "$LOGFILE"

# 5) Latency single op
START_NS=$(date +%s%N)
touch "$TEST_DIR/latency-test.txt"
END_NS=$(date +%s%N)
LAT_MS=$(( (END_NS - START_NS) / 1000000 ))
echo "Single touch latency: ${LAT_MS} ms" | tee -a "$LOGFILE"

# Cleanup
rm -rf "$TEST_DIR"

echo "=== VALIDATION COMPLETE: results saved to $LOGFILE" | tee -a "$LOGFILE"

exit 0
