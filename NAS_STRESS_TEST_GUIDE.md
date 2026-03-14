# 🔥 NAS Stress Test - Quick Reference

## Overview
Comprehensive stress testing suite for your NAS at **192.168.168.100** (eiq-nas).  
Tests network performance, I/O throughput, concurrent operations, and system reliability.

---

## Quick Start

### Run Quick Test (5 minutes)
```bash
bash scripts/nas-integration/stress-test-nas.sh --quick
```

### Run Moderate Test (15 minutes)  
```bash
bash scripts/nas-integration/stress-test-nas.sh --medium
```

### Run Aggressive Test (30 minutes - max load)
```bash
bash scripts/nas-integration/stress-test-nas.sh --aggressive
```

---

## Test Profiles

| Profile | Duration | File Size | Concurrent Ops | When to Use |
|---------|----------|-----------|----------------|------------|
| **--quick** | 5 min | 100 MB | 5-10 | Daily checks, CI/CD integration |
| **--medium** | 15 min | 500 MB | 15-30 | Weekly verification, baseline |
| **--aggressive** | 30 min | 1 GB | 30-50 | Pre-deployment validation, stress testing |

---

## Options

```bash
# With real-time monitoring (shows metrics during test)
bash scripts/nas-integration/stress-test-nas.sh --quick --monitor

# Without cleanup (keep test files for investigation)
bash scripts/nas-integration/stress-test-nas.sh --medium --nocleanup
```

---

## Environment Variables

```bash
# Override NAS configuration
NAS_HOST=192.168.168.39 \
NAS_USER=svc-nas \
NAS_PORT=22 \
NAS_KEY=~/.ssh/id_ed25519 \
  bash scripts/nas-integration/stress-test-nas.sh --quick
```

---

## Test Coverage

### 1. **Network Baseline**
- Ping latency (min/max/avg)
- 10 round-trip measurements
- Network path verification

### 2. **SSH Connection Stress**
- Concurrent SSH connection creation (5-30 parallel)
- Connection persistence
- Error recovery

### 3. **File Upload Throughput**
- 100-1000 MB file transfer to NAS
- Measures upload bandwidth (KB/s)
- Network saturation testing

### 4. **File Download Throughput**
- 100-1000 MB file retrieval from NAS
- Measures download bandwidth (KB/s)
- Read performance assessment

### 5. **Concurrent I/O Operations**
- Parallel file creation (50-200 files)
- Concurrent read operations (10-50 reads)
- Write throughput measurement
- Read throughput measurement

### 6. **Sustained Load Test**
- 5-30 minute continuous operations
- Mixed workload (touch, append, stat, ls, du)
- Error rate tracking
- Operation completion rate

### 7. **System Resource Monitoring**
- NAS CPU load average
- Memory usage on NAS
- Disk usage (test directory)
- Overall system health

---

## Output Interpretation

### Success Indicators (🟢 Excellent)
```
✓ Ping Avg: < 5ms
✓ SSH Success: 100%
✓ Upload: > 50 MB/s
✓ Download: > 50 MB/s
✓ Total Errors: 0
```

### Warning Signs (🟡 Warning)
```
⚠ Ping Avg: 10-20ms
⚠ SSH Success: 90-95%
⚠ Upload/Download: 10-50 MB/s
⚠ Errors: 1-10
```

### Critical Issues (🔴 Critical)
```
✗ Ping Avg: > 20ms
✗ SSH Success: < 90%
✗ Upload/Download: < 10 MB/s
✗ Errors: > 10
```

---

## Sample Results

```
===> TEST 1: Network Baseline (Ping & Latency)
  Min: 0.645ms
  Max: 1.238ms
  Avg: 0.89ms

===> TEST 2: SSH Connection Stress (5 concurrent)
SSH Connections: 5/5 successful

===> TEST 3: File Upload Throughput
Upload completed in 1.42s (70.42 KB/s)

===> TEST 4: File Download Throughput
Download completed in 1.38s (72.46 KB/s)

===> TEST 5: Concurrent Read/Write Operations
Created 50 files in 8.34s (59.95 MB/s)
Performed 10 concurrent reads in 0.94s (106.38 MB/s)

===> TEST 6: Sustained Load Test (300s)
Completed 1500 operations in 300s

===> 📊 STRESS TEST RESULTS SUMMARY
Network Performance
  Ping Min:       0.645ms
  Ping Max:       1.238ms
  Ping Avg:       0.89ms

Connection Performance
  SSH Success:    5/5
  SSH Failed:     0

Data Transfer Throughput
  Upload (KB/s):  70.42
  Download (KB/s): 72.46

I/O Performance
  Write (MB/s):   59.95
  Read (MB/s):    106.38

Health Assessment
  🟢 EXCELLENT - NAS performing optimally
```

---

## Troubleshooting

### SSH Connection Failed
```bash
# Check NAS connectivity
ping 192.168.168.100

# Test SSH manually
ssh -i ~/.ssh/id_ed25519 svc-nas@192.168.168.100 echo "OK"

# Verify key permissions
ls -la ~/.ssh/id_ed25519
```

### Test Directory Creation Failed
```bash
# Check NAS write permissions
ssh svc-nas@192.168.168.100 "ls -la /tmp"

# Check disk space
ssh svc-nas@192.168.168.100 "df -h"
```

### High Latency/Low Throughput
```bash
# Check NAS network interface
ssh svc-nas@192.168.168.100 "ethtool eth0" || "ip -s link"

# Monitor NAS CPU/memory during test
ssh svc-nas@192.168.168.100 "top -b -n 1"
```

### Test Files Not Cleaned Up
```bash
# Manual cleanup
ssh svc-nas@192.168.168.100 "rm -rf /tmp/nas-stress-test-*"
```

---

## Integration with Monitoring

### Export Results to Prometheus
The test results can be parsed for monitoring integration:
- Store min/max/avg ping times as gauges
- Track connection success rates
- Monitor throughput trends over time

### Scheduled Stress Testing
```bash
# Add to crontab for weekly testing
0 2 * * 0 cd /home/akushnir/self-hosted-runner && \
  bash scripts/nas-integration/stress-test-nas.sh --medium >> /var/log/nas-stress-test.log 2>&1
```

---

## Performance Baseline

Typical results for your setup:
- **Latency**: 1-3ms (local network)
- **Upload**: 50-100 MB/s (Gigabit Ethernet)
- **Download**: 50-100 MB/s (Gigabit Ethernet)
- **Connection Success**: 100% (no network issues)
- **Error Rate**: < 1%

---

## Additional Resources

- NAS Integration Guide: `NAS_INTEGRATION_GUIDE.md`
- Monitoring Setup: `NAS_MONITORING_INTEGRATION.md`
- Deployment Guide: `NAS_DEPLOYMENT_EXECUTION_GUIDE.md`

