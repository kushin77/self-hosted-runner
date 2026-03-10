# 📊 DEPLOYMENT MONITORING & OBSERVABILITY SETUP GUIDE

**Date**: March 4, 2026  
**Phase**: P0 & P1 Deployment Monitoring  
**Status**: Production-Ready Setup Guide

---

## 📋 TABLE OF CONTENTS

1. [Quick Start](#quick-start)
2. [Phase P0 Monitoring](#phase-p0-monitoring)
3. [Phase P1 Monitoring](#phase-p1-monitoring)
4. [Alert Configuration](#alert-configuration)
5. [Dashboards](#dashboards)
6. [Health Checks](#health-checks)
7. [Troubleshooting](#troubleshooting)

---

## 🚀 QUICK START

### Minimal Setup (5 minutes)
```bash
# 1. Setup health checks
chmod +x scripts/automation/pmo/deployment-validation.sh

# 2. Run validation
./scripts/automation/pmo/deployment-validation.sh --phase=p0 --check=all

# 3. Enable continuous monitoring
./scripts/automation/pmo/deployment-validation.sh --phase=p0 --watch=true

# 4. View logs
tail -f scripts/automation/pmo/logs/deployment-validation-*.log
```

### Production Setup (30 minutes)
See [Phase P0 Monitoring](#phase-p0-monitoring) and [Phase P1 Monitoring](#phase-p1-monitoring) sections below.

---

## 🔍 PHASE P0 MONITORING

### Components to Monitor

#### 1. Ephemeral Workspace Manager
**What to monitor**:
- Workspace creation latency (target: <100ms)
- Workspace cleanup success rate (target: 100%)
- Stale workspace count (target: 0)
- Orphaned process count (target: 0)

**Prometheus metrics**:
```yaml
ephemeral_manager_create_duration_seconds  # Gauge: workspace creation time
ephemeral_manager_cleanup_errors_total     # Counter: cleanup failures
ephemeral_manager_stale_workspaces         # Gauge: count of stale workspaces
ephemeral_manager_orphaned_processes       # Gauge: orphaned process count
```

**Alert rules**:
```yaml
- alert: EphemeralWorkspaceCreationLatency
  expr: ephemeral_manager_create_duration_seconds > 0.5
  for: 5m
  annotations:
    summary: "Workspace creation latency > 500ms"

- alert: WorkspaceCleanupFailures
  expr: rate(ephemeral_manager_cleanup_errors_total[5m]) > 0
  for: 1m
  annotations:
    summary: "Workspace cleanup failures detected"
```

#### 2. Capability Store
**What to monitor**:
- CRD registration success rate (target: 100%)
- Runner discovery latency (target: <100ms)
- Capability mismatch count (target: 0)
- Store query latency (target: <50ms)

**Prometheus metrics**:
```yaml
capability_store_registrations_total     # Counter: total registrations
capability_store_registration_errors     # Counter: registration failures
capability_store_discovery_duration      # Histogram: discovery latency
capability_store_mismatches_total        # Counter: capability mismatches
```

**Alert rules**:
```yaml
- alert: CapabilityStoreErrors
  expr: rate(capability_store_registration_errors_total[5m]) > 0
  for: 2m
  annotations:
    summary: "Capability store registration failures"

- alert: RunnerDiscoveryLatency
  expr: capability_store_discovery_duration > 0.5
  for: 5m
  annotations:
    summary: "Runner discovery latency > 500ms"
```

#### 3. OpenTelemetry Tracing
**What to monitor**:
- Trace export success rate (target: 100%)
- Span generation rate (target: consistent)
- Trace latency (target: <100ms)
- Collector availability (target: 99.9%)

**Prometheus metrics**:
```yaml
otel_spans_exported_total           # Counter: exported spans
otel_spans_dropped_total            # Counter: dropped spans
otel_export_duration_seconds        # Histogram: export latency
otel_collector_calls_total          # Counter: collector requests
otel_collector_errors_total         # Counter: collector errors
```

**Alert rules**:
```yaml
- alert: OTELSpansDropped
  expr: rate(otel_spans_dropped_total[5m]) > 0
  for: 2m
  annotations:
    summary: "OTEL traces being dropped"

- alert: OTELCollectorUnavailable
  expr: rate(otel_collector_errors_total[5m]) > 0.01
  for: 2m
  annotations:
    summary: "OTEL collector error rate elevated"
```

#### 4. Fair Job Scheduler
**What to monitor**:
- Queue depth (target: <50 jobs)
- Job wait time (target: <30 min for all jobs)
- Priority class distribution (P0: <5%, P1: <20%, P2: 75%, etc.)
- Starvation events (target: 0)

**Prometheus metrics**:
```yaml
scheduler_queue_depth                        # Gauge: jobs in queue
scheduler_job_wait_time_seconds              # Histogram: wait latency
scheduler_priority_class_count               # Gauge: jobs per class
scheduler_starvation_events_total            # Counter: starvation incidents
scheduler_anti_aging_rescue_events_total     # Counter: anti-aging activations
```

**Alert rules**:
```yaml
- alert: SchedulerQueueBacklog
  expr: scheduler_queue_depth > 100
  for: 10m
  annotations:
    summary: "Job queue backlog: {{ $value }} jobs"

- alert: JobStarvation
  expr: scheduler_job_wait_time_seconds{quantile="0.95"} > 1800  # 30 min
  for: 5m
  annotations:
    summary: "Jobs waiting >30 min in queue"
```

#### 5. Drift Detection & Auto-Remediation
**What to monitor**:
- Drift detection latency (target: <60s)
- False positive rate (target: <1%)
- Auto-remediation success rate (target: >95%)
- Audit trail completeness (target: 100%)

**Prometheus metrics**:
```yaml
drift_detector_check_duration_seconds       # Histogram: check latency
drift_detector_violations_found_total       # Counter: drift detected
drift_detector_false_positives_total        # Counter: false positives
drift_detector_remediation_attempts_total   # Counter: remediation attempts
drift_detector_remediation_success_total    # Counter: successful remediations
drift_detector_audit_events_total           # Counter: audit trail
```

**Alert rules**:
```yaml
- alert: DriftDetectionLatency
  expr: drift_detector_check_duration_seconds > 120
  for: 5m
  annotations:
    summary: "Drift detection latency > 2 min"

- alert: DriftRemediationFailures
  expr: drift_detector_remediation_attempts_total - drift_detector_remediation_success_total > 5
  for: 5m
  annotations:
    summary: "Drift remediation failures detected"

- alert: AuditTrailGaps
  expr: rate(drift_detector_audit_events_total[5m]) == 0
  for: 5m
  annotations:
    summary: "No audit events recorded - possible audit trail issue"
```

---

## 🔮 PHASE P1 MONITORING

### Components to Monitor

#### 1. Graceful Job Cancellation
**What to monitor**:
- SIGTERM success rate (target: >95%)
- Process cleanup success (target: 100%)
- Checkpoint save reliability (target: 100%)
- Zombie process count (target: 0)

**Prometheus metrics**:
```yaml
job_cancellation_sigterm_success_total       # Counter: successful SIGTERM
job_cancellation_sigkill_escalations_total   # Counter: SIGKILL escalations
job_cancellation_process_cleanup_errors      # Counter: cleanup failures
job_cancellation_checkpoint_saves_total      # Counter: saved checkpoints
job_cancellation_checkpoint_recoveries_total # Counter: recovered checkpoints
job_cancellation_zombie_processes            # Gauge: zombie count
```

**Alert rules**:
```yaml
- alert: JobCancellationSIGTERMFailure
  expr: rate(job_cancellation_sigterm_success_total[5m]) < 0.95
  for: 5m
  annotations:
    summary: "SIGTERM success rate below 95%"

- alert: ZombieProcesses
  expr: job_cancellation_zombie_processes > 10
  for: 5m
  annotations:
    summary: "High zombie process count: {{ $value }}"

- alert: CheckpointRecoveryFailures
  expr: rate(job_cancellation_checkpoint_saves_total[5m]) > rate(job_cancellation_checkpoint_recoveries_total[5m])
  for: 10m
  annotations:
    summary: "Checkpoint recovery failures - data loss risk"
```

#### 2. Secrets Rotation Vault Integration
**What to monitor**:
- Secret rotation success (target: 100%)
- TTL compliance (target: 100%)
- Credential cache hit rate (target: >80%)
- Rotation latency (target: <5s)
- Audit trail completeness (target: 100%)

**Prometheus metrics**:
```yaml
vault_rotation_attempts_total              # Counter: rotation attempts
vault_rotation_success_total               # Counter: successful rotations
vault_rotation_duration_seconds            # Histogram: rotation time
vault_credential_cache_hits_total          # Counter: cache hits
vault_credential_cache_misses_total        # Counter: cache misses
vault_credential_expired_count             # Gauge: expired credentials
vault_audit_events_total                   # Counter: audit entries
```

**Alert rules**:
```yaml
- alert: VaultRotationFailures
  expr: vault_rotation_attempts_total - vault_rotation_success_total > 3
  for: 5m
  annotations:
    summary: "Vault rotation failures detected"

- alert: ExpiredCredentialsInUse
  expr: vault_credential_expired_count > 0
  for: 1m
  annotations:
    summary: "{{ $value }} expired credentials still in use!"

- alert: VaultCacheMalfunction
  expr: rate(vault_credential_cache_misses_total[5m]) > rate(vault_credential_cache_hits_total[5m])
  for: 10m
  annotations:
    summary: "Vault cache is liabilities more misses than hits"

- alert: RotationLatencyHigh
  expr: vault_rotation_duration_seconds > 10
  for: 5m
  annotations:
    summary: "Credential rotation latency > 10 seconds"
```

#### 3. ML-Based Failure Prediction
**What to monitor**:
- Model accuracy (target: >90%)
- False positive rate (target: <5%)
- Prediction latency (target: <2s)
- Alert delivery success (target: 100%)
- Model staleness (target: <24h)

**Prometheus metrics**:
```yaml
failure_predictor_accuracy                 # Gauge: model accuracy %
failure_predictor_false_positives_total    # Counter: false alarms
failure_predictor_true_positives_total     # Counter: correct predictions
failure_predictor_prediction_duration      # Histogram: scoring latency
failure_predictor_alerts_sent_total        # Counter: alerts dispatched
failure_predictor_alerts_failed_total      # Counter: alert failures
failure_predictor_model_age_seconds        # Gauge: model staleness
failure_predictor_retraining_duration      # Histogram: training time
```

**Alert rules**:
```yaml
- alert: PredictionAccuracyDegraded
  expr: failure_predictor_accuracy < 90
  for: 10m
  annotations:
    summary: "Model accuracy dropped to {{ $value }}%"

- alert: FalsePositiveRateHigh
  expr: failure_predictor_false_positives_total / (failure_predictor_true_positives_total + failure_predictor_false_positives_total) > 0.05
  for: 5m
  annotations:
    summary: "False positive rate > 5%"

- alert: PredictionLatencyHigh
  expr: failure_predictor_prediction_duration > 5
  for: 5m
  annotations:
    summary: "Prediction latency > 5 seconds"

- alert: ModelStale
  expr: failure_predictor_model_age_seconds > 86400  # 24 hours
  for: 1h
  annotations:
    summary: "ML model not updated in 24 hours"

- alert: AlertDeliveryFailures
  expr: rate(failure_predictor_alerts_failed_total[5m]) > 0
  for: 2m
  annotations:
    summary: "Prediction alerts not being delivered"
```

---

## ⚙️ ALERT CONFIGURATION

### Alert Routing
Configure in `prometheus/alertmanager.yaml`:

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 4h
  
  routes:
    # Phase P0 critical alerts
    - match:
        phase: "p0"
        severity: "critical"
      receiver: 'p0-critical'
      continue: true
      repeat_interval: 1h
    
    # Phase P1 critical alerts
    - match:
        phase: "p1"
        severity: "critical"
      receiver: 'p1-critical'
      continue: true
      repeat_interval: 1h
    
    # Security-related alerts
    - match:
        category: "security"
      receiver: 'security-team'
      group_wait: 30s

receivers:
  - name: 'default'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_DEFAULT}'
        channel: '#platform-alerts'
  
  - name: 'p0-critical'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_CRITICAL}'
        channel: '#platform-critical'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
  
  - name: 'p1-critical'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_CRITICAL}'
        channel: '#platform-critical'
  
  - name: 'security-team'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_SECURITY}'
        channel: '#security-alerts'
    email_configs:
      - to: 'security-team@company.com'
```

### Severity Levels
- **CRITICAL**: Immediate action required (page on-call)
- **WARNING**: Attention needed within 1 hour
- **INFO**: Informational (log only)

---

## 📈 DASHBOARDS

### Phase P0 Dashboard
**Metrics to display**:
- Workspace creation latency (line chart)
- Cleanup success rate (gauge)
- Runner discovery latency (heatmap)
- Queue depth (line chart)
- Drift violations per hour (bar chart)
- Component health (status tiles)

**Grafana JSON**:
See `scripts/automation/pmo/prometheus/grafana-dashboards/phase-p0.json`

### Phase P1 Dashboard
**Metrics to display**:
- Job cancellation success rate (gauge)
- Credential rotation timeline (timeline)
- Prediction accuracy over time (line chart)
- Anomaly detection events (bar chart)
- False positive rate (gauge)
- Model staleness (gauge)

**Grafana JSON**:
See `scripts/automation/pmo/prometheus/grafana-dashboards/phase-p1.json`

### Integration Dashboard
**Metrics to display**:
- Cross-component latency (dependency graph)
- End-to-end job flow time (histogram)
- Error propagation chains (sankey)
- Resource utilization (stacked area chart)

---

## ✅ HEALTH CHECKS

### Deployment Validation Script
```bash
# Run all Phase P0 checks
./scripts/automation/pmo/deployment-validation.sh --phase=p0 --check=all

# Run all Phase P1 checks
./scripts/automation/pmo/deployment-validation.sh --phase=p1 --check=all

# Run integration checks
./scripts/automation/pmo/deployment-validation.sh --phase=both --check=all

# Continuous monitoring (refresh every 30s)
./scripts/automation/pmo/deployment-validation.sh --phase=p0 --watch=true
```

### Manual Health Checks
```bash
# Check Ephemeral Workspace Manager
./scripts/automation/pmo/ephemeral-workspace-manager.sh --status

# Check Capability Store
./scripts/automation/pmo/capability-store.sh --validate

# Check OTEL Tracing
./scripts/automation/pmo/otel-tracer.sh --health-check

# Check Fair Job Scheduler
./scripts/automation/pmo/fair-job-scheduler.sh --validate

# Check Drift Detector
./scripts/automation/pmo/drift-detector.sh --validate
```

---

## 🚨 TROUBLESHOOTING

### Phase P0 Issues

**Issue**: Workspace creation latency high
```bash
# Check for stuck processes
ps aux | grep "[e]phemeral"

# Check disk space
df -h /runners

# Check system load
top -b -n 1 | head -20

# Solution: Clear stale workspaces
./scripts/automation/pmo/ephemeral-workspace-manager.sh --cleanup-stale
```

**Issue**: Queue backlog growing
```bash
# Check scheduler status
./scripts/automation/pmo/fair-job-scheduler.sh --status

# Check for failing runners
curl http://localhost:8081/metrics | grep runner_failed

# Solution: Investigate failed runners
ssh runner-host "systemctl status 'actions.runner.*'"
```

**Issue**: Drift detector not finding violations
```bash
# Check drift detector logs
tail -f logs/drift-detector.log

# Verify git configuration
./scripts/automation/pmo/drift-detector.sh --validate

# Solution: Re-sync configuration
./scripts/automation/pmo/drift-detector.sh --force-sync
```

### Phase P1 Issues

**Issue**: Job cancellation timeouts
```bash
# Check for stuck processes
ps aux | grep "timeout\|SIGTERM"

# Increase grace period in config
vim scripts/automation/pmo/examples/.runner-config/job-cancellation.yaml
# Set: grace-period: 60s  (increase from default 30s)

# Solution: Restart cancellation handler
./scripts/automation/pmo/job-cancellation-handler.sh --restart
```

**Issue**: Vault credentials not rotating
```bash
# Check Vault connectivity
./scripts/automation/pmo/vault-integration.sh --test

# Check Vault AppRole auth
vault list auth/approle/role

# Check credential TTL
./scripts/automation/pmo/vault-integration.sh --status

# Solution: Re-authenticate
./scripts/automation/pmo/vault-integration.sh --auth
```

**Issue**: Prediction accuracy low
```bash
# Check model age
./scripts/automation/pmo/failure-predictor.sh --status | grep "model_age"

# Retrain model with fresh data
./scripts/automation/pmo/failure-predictor.sh --train --force

# Evaluate new model
./scripts/automation/pmo/failure-predictor.sh --evaluate

# Solution: Deploy new model
./scripts/automation/pmo/failure-predictor.sh --deploy
```

---

## 📞 SUPPORT

**Monitoring Questions?**
- Check this guide first (most answers here)
- Review component documentation
- Post in #platform-monitoring Slack channel

**Alert Tuning?**
- Adjust thresholds in alert rules
- Test in staging environment first
- Document reason for threshold change
- Notify platform team of changes

**Metrics Missing?**
- Verify component is exporting metrics
- Check Prometheus scrape config
- Verify Prometheus is collecting data
- See component documentation

---

**Status**: ✅ **PRODUCTION READY**  
**Last Updated**: March 4, 2026  
**Version**: 1.0

For deployment procedures, see [APPROVED_DEPLOYMENT.md](../APPROVED_DEPLOYMENT.md).
