# Phase P1 Operational Runbooks

## Table of Contents
1. Job Cancellation Handler (P1.1) - Runbook
2. Vault Integration (P1.2) - Runbook
3. Failure Prediction (P1.3) - Runbook
4. Integration Issues - Runbook
5. Emergency Procedures

---

## 1. Phase P1.1: Job Cancellation Handler Runbook

### Overview
Handles graceful job termination with resource cleanup and state preservation.

### Common Issues & Resolutions

#### Issue: Jobs not terminating after SIGTERM
**Symptoms**: Jobs keep running after 30-second grace period, requiring force kill
**Root Causes**: 
- Process not handling SIGTERM signals
- Child processes not in same process group
- I/O blocked in uninterruptible sleep

**Resolution Steps**:
```bash
# 1. Check process tree
ps auxf | grep -A 10 [job-id]

# 2. Verify signal handling
strace -e signal -p [pid]

# 3. Check for uninterruptible sleep
cat /proc/[pid]/status | grep State

# 4. Manually escalate to SIGKILL if needed
kill -9 [pid]

# 5. Check for zombie processes
ps aux | grep defunct

# 6. If zombies exist, kill parent
kill -9 [parent-pid]
```

**Prevention**:
- Run jobs in isolated containers/cgroups
- Use timeout wrapper for all long-running tasks
- Monitor SIGTERM handling regularly

#### Issue: Checkpoint recovery failure - state loss
**Symptoms**: "Checkpoint recovery failed for job X", job state not recoverable
**Root Causes**:
- Checkpoint file corrupted
- Disk space exhausted
- Permissions issues

**Resolution Steps**:
```bash
# 1. Verify checkpoint files
ls -la .job-checkpoints/

# 2. Validate checkpoint JSON
jq . .job-checkpoints/job-[id].checkpoint

# 3. Check disk space
df -h .job-checkpoints/
du -sh .job-checkpoints/

# 4. Fix permissions if needed
chmod 700 .job-checkpoints/
chmod 600 .job-checkpoints/*.checkpoint

# 5. Clean old checkpoints (>7 days)
find .job-checkpoints/ -mtime +7 -delete

# 6. Manually recover from backup if available
tar -xzf /var/backups/job-checkpoints-backup.tar.gz
```

**Prevention**:
- Monitor checkpoint directory size
- Regularly clean old checkpoints
- Implement checkpoint rotation

#### Issue: Job timeout not enforced
**Symptoms**: Job runs beyond JOB_TIMEOUT value
**Root Causes**:
- Timeout value not set
- Job spawning child processes in detached mode
- Timeout signal not reaching process group

**Resolution Steps**:
```bash
# 1. Verify timeout is set
echo $JOB_TIMEOUT

# 2. Check if job is in separate process group
ps -j -p [job-pid]

# 3. Set timeout before job execution
export JOB_TIMEOUT=3600

# 4. Verify timeout enforcement
./job-cancellation-handler wrapper "test-job" "sleep 9000" &
sleep 5
ps aux | grep sleep

# 5. Manually terminate if needed
kill -TERM -[pgid]
```

**Prevention**:
- Always set JOB_TIMEOUT environment variable
- Use timeout wrapper for all job types
- Monitor timeout enforcement metrics

### Monitoring & Health Checks

```bash
# Health check endpoint
./job-cancellation-handler check [job-id]

# View recent checkpoint saves
tail -50 $(find .job-checkpoints/ -name "*.json" -printf '%T@ %p\n' | sort -r | head -1 | cut -d' ' -f2-)

# Monitor exit codes
grep -r "exit_code" .job-checkpoints/ | awk '{print $NF}' | sort | uniq -c

# Check for resource leaks
cat /proc/[pid]/maps | wc -l  # Should be < 50
lsof -p [pid] | wc -l         # Should be < 20
```

---

## 2. Phase P1.2: Vault Secrets Integration Runbook

### Overview
Manages credential rotation with 6-hour TTL and audit compliance.

### Common Issues & Resolutions

#### Issue: Authentication failure - "Failed to authenticate with Vault"
**Symptoms**: Credential operations fail with auth errors
**Root Causes**:
- Wrong VAULT_ADDR
- Invalid ROLE_ID or SECRET_ID
- Network connectivity issues
- Vault server down

**Resolution Steps**:
```bash
# 1. Verify Vault connectivity
curl -v $VAULT_ADDR/v1/sys/health

# 2. Check configuration
echo "VAULT_ADDR: $VAULT_ADDR"
echo "VAULT_ROLE_ID: ${VAULT_ROLE_ID:0:10}..."
echo "SECRET_ID file: $(ls -la $VAULT_SECRET_ID_PATH)"

# 3. Test AppRole auth manually
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{\"role_id\": \"$VAULT_ROLE_ID\", \"secret_id\": \"$(cat $VAULT_SECRET_ID_PATH)\"}" \
  $VAULT_ADDR/v1/auth/approle/login

# 4. Check Vault logs
curl -H "X-Vault-Token: $TOKEN" $VAULT_ADDR/v1/sys/audit/http | jq '.

# 5. Restart Vault if needed (requires operator access)
# See Vault operational procedures

# 6. Regenerate credentials if compromised
# Contact security team to issue new SECRET_ID
```

**Prevention**:
- Monitor Vault server uptime
- Test auth regularly
- Use health check in deployment

#### Issue: Credential expiration - "Expired credentials detected"
**Symptoms**: Jobs fail with authentication errors, "TTL exceeded"
**Root Causes**:
- Rotation daemon crashed
- TTL too short for job duration
- Cache eviction
- System clock skew

**Resolution Steps**:
```bash
# 1. Check daemon status
ps aux | grep vault-integration

# 2. Verify daemon is running
./vault-integration status

# 3. Check credential cache
ls -lah $(echo $CREDENTIAL_CACHE_DIR)/*.secret

# 4. View TTL metadata
for f in $CREDENTIAL_CACHE_DIR/*.secret; do
  echo "=== $f ===" 
  jq '.expires_at' "$f"
done

# 5. Force manual rotation for expired credentials
./vault-integration rotate secret/data/runners/token

# 6. Increase TTL if jobs require longer duration
export CREDENTIAL_TTL=86400  # 24 hours

# 7. Restart rotation daemon
pkill -f "vault-integration daemon"
./vault-integration daemon &

# 8. Check system clock
timedatectl status
# If clock is wrong, adjust: timedatectl set-time "2026-03-04 12:00:00"
```

**Prevention**:
- Set TTL > max job duration
- Monitor rotation daemon health
- Use NTP for clock synchronization

#### Issue: Cache hit rate low - "Cache performance degraded"
**Symptoms**: High latency in credential fetching, slow job startup
**Root Causes**:
- Cache directory full
- Excessive credentials in use
- Cache invalidation too aggressive
- Vault server slow

**Resolution Steps**:
```bash
# 1. Check cache size and content
du -sh $CREDENTIAL_CACHE_DIR
ls -la $CREDENTIAL_CACHE_DIR | wc -l

# 2. Clean old cached credentials
find $CREDENTIAL_CACHE_DIR -mtime +1 -delete

# 3. Monitor cache hit ratio
# From monitoring system, check vault_cache_hit_rate metric

# 4. If consistently low (<80%), increase cache TTL
export CREDENTIAL_TTL=43200  # 12 hours

# 5. Profile credential fetching latency
time ./vault-integration fetch secret/data/runners/test-token test

# 6. If latency is high, check Vault server
# From Vault: check API latency metrics
```

**Prevention**:
- Monitor cache metrics continuously
- Set TTL based on job patterns
- Implement intelligent cache eviction

#### Issue: Audit log full - "Disk space critical"
**Symptoms**: "AuditLogFull" alert, audit operations start failing
**Root Causes**:
- Audit verbosity too high
- Log rotation not configured
- Disk too small for workload

**Resolution Steps**:
```bash
# 1. Check audit log size
du -sh $AUDIT_LOG
df -h $(dirname $AUDIT_LOG)

# 2. Archive old logs
gzip $AUDIT_LOG
mv $AUDIT_LOG.gz /var/log/archive/vault-$(date +%Y%m%d).log.gz

# 3. Reinitialize log
touch $AUDIT_LOG
chmod 600 $AUDIT_LOG

# 4. Configure logrotate
cat >> /etc/logrotate.d/vault-integration << 'EOF'
$AUDIT_LOG {
  daily
  rotate 7
  compress
  delaycompress
  notifempty
}
EOF

# 5. Check audit verbosity and reduce if needed
# Reduce logging level in vault-integration.sh
# Change: log "INFO" → log "WARN"
```

**Prevention**:
- Configure logrotate for audit logs
- Monitor log size regularly
- Set appropriate verbosity level

### Monitoring & Health Checks

```bash
# Status checks
./vault-integration status

# Manual credential fetch with timing
time ./vault-integration fetch secret/data/runners/token test

# Verify rotation daemon
pgrep -f "vault-integration daemon"

# Check audit trail
tail -100 $AUDIT_LOG

# Cache statistics
ls -1 $CREDENTIAL_CACHE_DIR/*.secret | wc -l
```

---

## 3. Phase P1.3: Failure Prediction Runbook

### Overview
Detects job anomalies and predicts failures 1-2 minutes advance

### Common Issues & Resolutions

#### Issue: Model accuracy degraded - "Accuracy below 85%"
**Symptoms**: False positives increasing, missed failures
**Root Causes**:
- Training data stale
- Feature distribution changed
- Model overfitting/underfitting
- System behavior changed

**Resolution Steps**:
```bash
# 1. Check model age
ls -la $(echo $MODEL_PATH)

# 2. Evaluate on recent data
./failure-predictor evaluate ./recent-job-features.csv

# 3. Review model metrics
# Should show: precision >.95, recall >.90

# 4. If accuracy low, retrain model
./failure-predictor train ./recent-historical-data.csv

# 5. Verify new model
./failure-predictor evaluate ./test-features.csv

# 6. If still low, check feature extraction
# May indicate system changes requiring new features
```

**Prevention**:
- Retrain model daily
- Monitor accuracy continuously
- Track system changes that affect features

#### Issue: High false positive rate - "Alert fatigue"
**Symptoms**: Many alerts for jobs that complete successfully
**Root Causes**:
- Threshold too low
- Feature extraction noisy
- Threshold not calibrated to current workload

**Resolution Steps**:
```bash
# 1. Check anomaly threshold
echo $ANOMALY_THRESHOLD   # Currently 0.7

# 2. Analyze false positive distribution
# Query database: SELECT * FROM predictions WHERE is_false_positive = 1

# 3. If >5% false positives, increase threshold
export ANOMALY_THRESHOLD=0.75

# 4. Alternatively, improve model
./failure-predictor train --with-feature-engineering

# 5. Test new threshold on recent data
foreach job in failed_jobs; do
  ./failure-predictor score $job
done

# 6. Verify reduced false positives
```

**Prevention**:
- Monitor false positive rate continuously
- Adjust threshold quarterly
- Implement calibration process

#### Issue: Anomaly not detected - "Missed failure"
**Symptoms**: Job fails without preceding alert
**Root Causes**:
- Feature not extracted
- Score below threshold
- Webhook delivery failed
- Model gap in coverage

**Resolution Steps**:
```bash
# 1. Check if features were extracted
sqlite3 $METRICS_DB "SELECT * FROM predictions WHERE job_id='[job-id]';"

# 2. Review anomaly score
# If score < 0.7, feature extraction may be incomplete

# 3. Check webhook delivery
grep -i webhook $(echo $LOG_FILE)

# 4. If delivery failed, check webhook endpoint
curl -X POST http://[webhook-addr] -d '{"test": "alert"}'

# 5. Retrain model with this failure case
# Add job features to training set marked as failure=1

# 6. Verify model now detects similar patterns
./failure-predictor evaluate ./test-with-new-failure.csv
```

**Prevention**:
- Continuous model improvement
- Include missed failures in retraining
- Monitor model coverage metrics

#### Issue: Model training failed - "Training crashed"
**Symptoms**: "Training failed" in logs, old model still in use
**Root Causes**:
- Insufficient memory
- Training data corrupted
- Library version mismatch
- Insufficient successful jobs for training

**Resolution Steps**:
```bash
# 1. Check training logs
grep -i error $(echo $LOG_FILE) | tail -20

# 2. Verify training data
head -5 ./training-data.csv
wc -l ./training-data.csv

# 3. Check available memory
free -h

# 4. Try training with reduced data
head -10000 ./training-data.csv > ./training-small.csv
./failure-predictor train ./training-small.csv

# 5. If memory issue, increase system resources or reduce batch size

# 6. Verify library versions
python3 -c "import sklearn; print(sklearn.__version__)"
python3 -c "import pandas; print(pandas.__version__)"

# 7. If version mismatch, update: pip install scikit-learn==x.x.x

# 8. Schedule training during low-load period
(crontab -l; echo "0 2 * * * /path/to/failure-predictor train /path/to/data") | crontab -
```

**Prevention**:
- Pre-check training prerequisites
- Monitor training resource usage
- Schedule during off-peak hours

### Monitoring & Health Checks

```bash
# Service status
ps aux | grep failure-predictor

# Model information
ls -lah $MODEL_PATH

# Recent predictions
sqlite3 $METRICS_DB "SELECT * FROM predictions ORDER BY timestamp DESC LIMIT 10;"

# Accuracy metrics
./failure-predictor evaluate ./current-test-set.csv
```

---

## 4. Integration Issues Runbook

### Issue: All three components failing - Multi-component failure
**Symptoms**: Jobs failing with multiple component errors
**Root Causes**:
- System resource exhaustion
- Network outage
- Multiple dependencies down
- Configuration corruption

**Resolution Steps**:
```bash
# 1. Check system health
free -h
df -h
ps aux --sort=-%cpu | head -10

# 2. Check network connectivity
ping 8.8.8.8
curl https://status.github.com

# 3. Verify each component
./job-cancellation-handler check "test"
./vault-integration status
ps aux | grep failure-predictor

# 4. Check logs for correlation
grep ERROR *.log
grep -i "component failure" *.log

# 5. Restart components in order
systemctl restart elevation-github-runner  # Restarts all P1 components

# 6. Verify recovery
sleep 5
./production-deployment status
```

**Prevention**:
- Implement component health checks
- Monitor resource usage
- Test failure scenarios regularly

---

## 5. Emergency Procedures

### Emergency Rollback
If critical issues detected during deployment:

```bash
./deploy-p1-production.sh rollback
```

### Manual Component Restart
```bash
# Restart job cancellation handler
systemctl restart run-safe.sh

# Restart vault integration daemon
pkill -f "vault-integration daemon"
./vault-integration daemon &

# Restart failure predictor monitoring
pkill -f "failure-predictor monitor"
./failure-predictor monitor &
```

### Manual Credential Rotation (if daemon fails)
```bash
./vault-integration daemon .runner-config/vault-rotation.yaml
```

### Alert Channels
- **Slack**: #p1-deployment
- **PagerDuty**: p1-oncall@
- **Email**: ops-team@

---

## Escalation Paths

| Issue Level | Owner | Contact | Response Time |
|-------------|-------|---------|----------------|
| Warning    | On-Call Eng | Slack   | 15 min        |
| High       | Component Owner | PagerDuty | 5 min        |
| Critical   | Platform Lead | Page Lead + Slack | 2 min        |

---

## Appendix: Quick Reference Commands

```bash
# Status
./deploy-p1-production.sh status
./vault-integration status
./failure-predictor monitor

# Testing
./job-cancellation-handler check [job-id]
./vault-integration fetch secret/data/test test-secret

# Logs
tail -f /var/log/p1-deployment.log
tail -f $(echo $AUDIT_LOG)
tail -f $(echo $LOG_FILE)

# Cleanup
find .job-checkpoints/ -mtime +7 -delete

# Metrics
sqlite3 /var/lib/runner-metrics.db "SELECT COUNT(*) FROM predictions;"
```
