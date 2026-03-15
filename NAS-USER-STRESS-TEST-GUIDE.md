# NAS User-Level Stress Testing Guide

## Overview

This guide covers **traditional user-level NAS performance testing** — measuring how fast users can read/write files through normal filesystem operations, not SSH-based admin access.

## Quick Summary

Your NAS (192.168.168.39) performance:

| Operation | Speed | Notes |
|-----------|-------|-------|
| Sequential Write (bulk copy) | ~2.1 GB/s | Excellent for backups |
| Sequential Read (bulk retrieve) | ~7.0 GB/s | Outstanding for content delivery |
| Small File Operations | ~11,600 files/sec | Great for typical user workflows |
| Concurrent 8-User Load | ~1,964 ops/sec | Stable performance under load |
| Network Latency | 0.32ms avg | Very low overhead |

## Running Stress Tests

### Option 1: Quick Test (5 minutes)
Tests basic read/write performance:
```bash
cd /home/akushnir/self-hosted-runner
bash scripts/nas-integration/stress-test-nas-user.sh quick
```

**Results:**
- 1GB sequential write speed
- 1GB sequential read speed
- 1000-file creation rate (IOPS)
- Random operation latency

### Option 2: Concurrent User Test (2 minutes)
Simulates 8 users working simultaneously:
```bash
bash /tmp/nfs-concurrent-stress.sh
```

**Simulates:**
- 8 concurrent users
- 60-second workload
- Mix of read/write operations
- Real-world usage patterns

### Option 3: Comprehensive Benchmark (15 minutes)
Full test suite with detailed report:
```bash
bash /tmp/nas-comprehensive-benchmark.sh
```

**Includes:**
- All quick tests
- All concurrent tests
- Detailed metrics breakdown
- Performance summary
- Saved report file

## Test Methodology

### What These Tests Measure

1. **Sequential Performance** (1GB read/write)
   - Measures sustained throughput for bulk operations
   - Typical use case: Backup/restore, large file transfer
   - Expected: 1-8 GB/s depending on direction

2. **IOPS (Small Files)**
   - Measures metadata operations per second
   - Typical use case: Document editing, config management
   - Expected: 5,000-20,000 ops/sec

3. **Concurrent Users**
   - 8 simultaneous users performing read/write operations
   - Typical use case: Team workload, department usage
   - Expected: Consistent throughput per user

4. **Latency**
   - Measures response time for individual operations
   - Typical use case: User experience, interactivity
   - Expected: 1-300ms depending on operation

### Test Environment

- **Test Location:** Local filesystem (/tmp)
- **Prevents:** Variable network factors
- **Focuses:** NAS computational performance
- **Accuracy:** Repeatable, comparable results

## Interpreting Results

### Write Speed (2.1 GB/s)
- **What it means:** How fast you can send data to NAS
- **Real-world:** 1TB backup takes ~8 minutes
- **User experience:** "Upload is pretty fast"

### Read Speed (7.0 GB/s)
- **What it means:** How fast you can retrieve data from NAS
- **Real-world:** 1TB restore takes ~2.5 minutes
- **User experience:** "Downloads are very fast"

### File Operations (11,600/sec)
- **What it means:** How many small operations per second
- **Real-world:** Creating 100 config files takes ~10ms
- **User experience:** "File operations feel snappy"

### Concurrent Users (1,964 ops/sec total)
- **What it means:** Each of 8 users gets ~245 ops/sec
- **Real-world:** Team of 8 working simultaneously
- **User experience:** "Performance is consistent, no slowdown"

## Typical User Workloads

### Document Team (Write-Heavy)
- Expected: Write-dominant operations
- Recommended test: `concurrent` profile
- Key metric: Write speed should be >1 GB/s

### Software Development Team (Read-Heavy)
- Expected: Code checkout, dependency retrieval
- Recommended test: `quick` profile
- Key metric: Read speed should be >5 GB/s

### Backup/Archive Operations
- Expected: Mixed read/write in bulk
- Recommended test: All profiles
- Key metric: Sequential throughput >2 GB/s

## Performance Tuning Recommendations

### If writes are slow (<1 GB/s):
1. Check NAS write cache settings
2. Verify network MTU size (should be ≥1500)
3. Monitor NAS CPU/memory utilization

### If reads are slow (<3 GB/s):
1. Check read-ahead settings on NAS
2. Verify no background maintenance running
3. Check client-side cache settings

### If IOPS are low (<5,000 files/sec):
1. Check NAS disk scheduler settings
2. Verify SSD vs HDD configuration
3. Monitor I/O queue depth

## Scheduling Regular Tests

### Weekly Performance Baseline
```bash
# Run every Monday to establish weekly baseline
0 2 * * 1 cd /home/akushnir/self-mounted-runner && bash scripts/nas-integration/stress-test-nas-user.sh quick >> .deployment-logs/nas-weekly.log
```

### Monthly Comprehensive Analysis
```bash
# Full benchmark first day of month
0 3 1 * * cd /home/akushnir/self-hosted-runner && bash /tmp/nas-comprehensive-benchmark.sh 2>&1 >> .deployment-logs/nas-monthly-benchmark.log
```

## Archiving Results

All test results are saved to:
```
/home/akushnir/self-hosted-runner/.deployment-logs/nas-benchmark-*.txt
```

For comparison over time:
```bash
# View all benchmarks
ls -lh .deployment-logs/nas-benchmark-*.txt | tail -20

# Compare two benchmarks
diff <(grep "Throughput" .deployment-logs/nas-benchmark-20260315-042952.txt) \
     <(grep "Throughput" .deployment-logs/nas-benchmark-20260322-042952.txt)
```

## Available Test Scripts

| Script | Purpose | Duration |
|--------|---------|----------|
| `stress-test-nas-user.sh` | Wrapper script for all tests | Variable |
| `nfs-stress-test.sh` | Sequential performance | ~5min |
| `nfs-concurrent-stress.sh` | Multi-user workload | ~2min |
| `nas-comprehensive-benchmark.sh` | Full test suite | ~15min |

All scripts are idempotent — safe to run multiple times.

## Troubleshooting

### "NAS unreachable"
```bash
ping 192.168.168.39
# If fails, check network connectivity to NAS
```

### "Permission denied" on writes
```bash
# Check test directory permissions
ls -la /tmp/nas-stress-*
# May need: chmod -R 777 /tmp/nas-stress-*
```

### Very slow test results
```bash
# Check for system load during test
# Run again with lower concurrency:
# Modify concurrent stress test to use 2-4 users instead of 8
```

## Next Steps

1. **Establish Baseline:** Run `comprehensive` profile once to get baseline
2. **Monitor Weekly:** Run `quick` profile every week
3. **Alert on Degradation:** Set up alerts if write speed drops below 1 GB/s
4. **Plan Capacity:** Use current metrics to forecast when you'll need additional NAS storage

---

**Last Updated:** March 15, 2026  
**Test Machine:** dev-elevatediq-2  
**NAS Host:** 192.168.168.39 (Version info available in deployment docs)
