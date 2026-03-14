#!/bin/bash
# 🔥 NAS STRESS TEST - QUICK COMMAND REFERENCE
# Save this for easy copy-paste access

# ============================================================================
# QUICK START (Copy & Paste These)
# ============================================================================

# Navigate to repo
cd /home/akushnir/self-hosted-runner

# Run 5-minute stress test (RECOMMENDED START HERE)
bash deploy-nas-stress-tests.sh --quick

# Run 15-minute stress test
bash deploy-nas-stress-tests.sh --medium

# Run 30-minute stress test
bash deploy-nas-stress-tests.sh --aggressive

# View results dashboard
bash deploy-nas-stress-tests.sh --dashboard

# ============================================================================
# SIMULATOR MODE (Works Now - No NAS Required)
# ============================================================================

# Quick simulator test
bash scripts/nas-integration/nas-stress-framework.sh simulate --quick

# Medium simulator test
bash scripts/nas-integration/nas-stress-framework.sh simulate --medium

# Aggressive simulator test
bash scripts/nas-integration/nas-stress-framework.sh simulate --aggressive

# ============================================================================
# LIVE MODE (When NAS is Reachable)
# ============================================================================

# Quick live test against real NAS
bash scripts/nas-integration/nas-stress-framework.sh live --quick

# Medium live test
bash scripts/nas-integration/nas-stress-framework.sh live --medium

# ============================================================================
# RESULTS & ANALYSIS
# ============================================================================

# View all results files
ls -lh nas-stress-results/

# View latest result (pretty JSON)
cat nas-stress-results/nas-stress-*.json | jq . | tail -50

# View only metr ics
cat nas-stress-results/nas-stress-*.json | jq '.metrics'

# View only test results
cat nas-stress-results/nas-stress-*.json | jq '.tests'

# Show performance trends
bash scripts/nas-integration/nas-stress-framework.sh trends

# ============================================================================
# PROMETHEUS METRICS EXPORT
# ============================================================================

# Export metrics for Prometheus scraping
EXPORT_METRICS=true bash deploy-nas-stress-tests.sh --quick

# View exported metrics
cat nas-stress-results/nas-stress-*.prom

# ============================================================================
# DOCKER/KUBERNETES TESTING
# ============================================================================

# Run stress test from worker node
ssh automation@192.168.168.42 \
  "cd /home/akushnir/self-hosted-runner && \
   bash deploy-nas-stress-tests.sh --quick"

# ============================================================================
# CUSTOM CONFIGURATION
# ============================================================================

# Override NAS host
NAS_HOST=192.168.168.39 bash deploy-nas-stress-tests.sh --quick

# Override SSH key
NAS_KEY=~/.ssh/svc-keys/elevatediq-svc-42-nas_key bash deploy-nas-stress-tests.sh --quick

# Combine custom settings
NAS_HOST=192.168.168.39 \
NAS_USER=svc-nas \
NAS_KEY=~/.ssh/svc-keys/elevatediq-svc-42-nas_key \
  bash deploy-nas-stress-tests.sh --medium

# ============================================================================
# SCHEDULED EXECUTION (Crontab)
# ============================================================================

# Daily stress test at 2 AM
0 2 * * * cd /home/akushnir/self-hosted-runner && \
  bash deploy-nas-stress-tests.sh --quick >> /var/log/nas-stress.log 2>&1

# Weekly stress test at 3 AM on Sunday
0 3 * * 0 cd /home/akushnir/self-hosted-runner && \
  bash deploy-nas-stress-tests.sh --medium >> /var/log/nas-stress.log 2>&1

# To add: crontab -e, then paste lines above

# ============================================================================
# DEBUGGING & TROUBLESHOOTING
# ============================================================================

# Check if NAS is reachable
ping 192.168.168.100

# Test SSH to NAS
ssh -i ~/.ssh/svc-keys/elevatediq-svc-42-nas_key \
  svc-nas@192.168.168.100 echo "SSH OK"

# Check available SSH keys
ls -la ~/.ssh/svc-keys/ | grep nas

# View test logs
tail -f nas-stress-results/nas-stress-*.json

# Check network connectivity
traceroute 192.168.168.100

# Check NAS system load
ssh svc-nas@192.168.168.100 "uptime && free -h && df -h"

# ============================================================================
# MONITORING INTEGRATION
# ============================================================================

# Add Prometheus scrape job for stress test metrics
# See: NAS_STRESS_TEST_COMPLETE_GUIDE.md for details

# Create Grafana dashboard from metrics
# Import JSON results or Prometheus queries

# ============================================================================
# HELP & DOCUMENTATION
# ============================================================================

# View quick reference
cat NAS_STRESS_TEST_GUIDE.md

# View complete documentation
cat NAS_STRESS_TEST_COMPLETE_GUIDE.md

# View implementation summary
cat NAS-STRESS-TEST-IMPLEMENTATION-SUMMARY.md

# Show deployment help
bash deploy-nas-stress-tests.sh --help

# ============================================================================
# FILE LOCATIONS
# ============================================================================

# Scripts
# - deploy-nas-stress-tests.sh
# - scripts/nas-integration/stress-test-nas.sh
# - scripts/nas-integration/nas-stress-framework.sh

# Documentation
# - NAS_STRESS_TEST_GUIDE.md
# - NAS_STRESS_TEST_COMPLETE_GUIDE.md
# - NAS-STRESS-TEST-IMPLEMENTATION-SUMMARY.md

# Results
# - nas-stress-results/nas-stress-YYYYMMDD_HHMMSS.json
# - nas-stress-results/nas-stress-YYYYMMDD_HHMMSS.prom

# ============================================================================
# COMMON WORKFLOWS
# ============================================================================

# Workflow 1: Quick Daily Validation
cd /home/akushnir/self-hosted-runner && \
bash deploy-nas-stress-tests.sh --quick && \
bash deploy-nas-stress-tests.sh --dashboard

# Workflow 2: Weekly Comprehensive Test
cd /home/akushnir/self-hosted-runner && \
bash deploy-nas-stress-tests.sh --medium && \
EXPORT_METRICS=true bash deploy-nas-stress-tests.sh --medium && \
bash deploy-nas-stress-tests.sh --dashboard

# Workflow 3: Pre-Deployment Stress Test
cd /home/akushnir/self-hosted-runner && \
bash deploy-nas-stress-tests.sh --aggressive && \
cat nas-stress-results/nas-stress-*.json | jq '.test_run.nas_accessible'

# Workflow 4: Performance Trending
cd /home/akushnir/self-hosted-runner && \
bash deploy-nas-stress-tests.sh --quick && \
bash scripts/nas-integration/nas-stress-framework.sh trends

# ============================================================================
# QUICK FACTS
# ============================================================================

# Test Duration Options:
# - Quick:      5 minutes (recommended to start)
# - Medium:     15 minutes (weekly validation)
# - Aggressive: 30 minutes (pre-deployment)

# Test Coverage:
# 1. Network Baseline      (ping latency, connectivity)
# 2. SSH Connection Stress (concurrent sessions)
# 3. Upload Throughput     (file transfer performance)
# 4. Download Throughput   (read performance)
# 5. Concurrent I/O        (parallel operations)
# 6. Sustained Load Test   (60-900 sec continuous)
# 7. System Resources      (CPU, memory, disk)

# Expected Results (Simulator):
# - Latency:    0.5-1.0ms
# - Throughput: 65,000 KB/s
# - I/O Ops:    1500 operations
# - Success:    99.8%
# - Status:     🟢 EXCELLENT

# ============================================================================
# 🚀 READY TO START?
# ============================================================================

# Copy and paste this to get started:
# 
#   cd /home/akushnir/self-hosted-runner
#   bash deploy-nas-stress-tests.sh --quick
#
# Then view results:
#   bash deploy-nas-stress-tests.sh --dashboard

echo "🔥 NAS Stress Test Suite - Quick Reference Ready"
echo "See this file for copy-paste commands"
