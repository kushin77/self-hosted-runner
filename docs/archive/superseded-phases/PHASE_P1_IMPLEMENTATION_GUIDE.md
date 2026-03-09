# Phase P1 Complete Implementation Guide

## Overview
This guide provides complete implementation details for all Phase P1 components, configuration examples, and troubleshooting procedures.

## Components

### Phase P1.1: Graceful Job Cancellation Handler
**Purpose**: Ensures jobs terminate cleanly with resource cleanup and state preservation

**Key Features**:
- SIGTERM signal handling with 30-second grace period
- Process tree cleanup with SIGKILL escalation
- Checkpoint save/restore for recovery
- GitHub Actions job wrapper
- Health check endpoints

**Deployment Location**: `/opt/runner/handlers/job-cancellation-handler.sh`
**Configuration**: `.runner-config/job-cancellation.yaml`

**Configuration Example**:
```yaml
job_cancellation:
  grace_period_seconds: 30
  checkpoint_dir: "/var/lib/job-checkpoints"
  max_child_processes: 100
  timeout_enforcement: true
  default_timeout: 3600
  sigkill_delay: 5  # seconds after grace period
  
  monitoring:
    health_check_interval: 60
    send_metrics: true
    export_to: "prometheus"
```

**Usage**:
```bash
# Run wrapped job
./job-cancellation-handler wrapper "test-job" "pytest tests/"

# Check job health
./job-cancellation-handler check "job-12345"

# Clean old checkpoints
./job-cancellation-handler cleanup-checkpoints
```

---

### Phase P1.2: Vault Secrets Rotation Integration
**Purpose**: Automated credential lifecycle management with 6-hour TTL enforcement

**Key Features**:
- AppRole authentication (production-safe)
- Automatic credential rotation daemon
- Multi-level caching
- Comprehensive audit logging
- TTL enforcement

**Deployment Location**: `/opt/runner/integrations/vault-integration.sh`
**Configuration**: `.runner-config/vault-rotation.yaml`

**Configuration Example**:
```yaml
vault:
  server_url: "https://vault.internal:8200"
  timeout: 10
  retry:
    max_attempts: 3
    backoff_multiplier: 2

authentication:
  method: "approle"
  role_id_file: "/run/vault/.role-id"
  secret_id_file: "/run/vault/.secret-id"
  cache_duration: 3600

credentials:
  - name: "github-token"
    path: "secret/data/runners/github-token"
    ttl: 21600  # 6 hours
    usage: "github-actions"
    
  - name: "docker-credentials"
    path: "secret/data/runners/docker-creds"
    ttl: 21600
    usage: "container-registry"
    
  - name: "npm-registry-token"
    path: "secret/data/runners/npm-token"
    ttl: 21600
    usage: "package-registry"

rotation:
  interval: 3600  # Check every hour
  daemon_mode: true
  restart_on_rotation: false  # Don't restart jobs

caching:
  directory: "/tmp/vault-credentials"
  mode: "504"
  max_files: 100

audit:
  log_all_operations: true
  log_file: "/var/log/vault-operations.log"
  retention_days: 90
  log_sensitive_data: false
```

**Usage**:
```bash
# Authenticate with Vault
./vault-integration auth

# Fetch a credential
./vault-integration fetch secret/data/runners/token github-token

# Start rotation daemon
./vault-integration daemon .runner-config/vault-rotation.yaml &

# Check status
./vault-integration status

# Clean up credentials on exit
./vault-integration cleanup
```

**Vault Policy Template** (for admins to configure):
```hcl
path "secret/data/runners/*" {
  capabilities = ["read", "list"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}
```

---

### Phase P1.3: ML-Based Failure Prediction Service
**Purpose**: Detect impending job failures 1-2 minutes in advance with anomaly detection

**Key Features**:
- Real-time feature extraction from job metrics
- Isolation Forest anomaly scoring
- Multi-level alerts (low, medium, high, critical)
- Daily model retraining
- Webhook integration for auto-remediation

**Deployment Location**: `/opt/runner/services/failure-predictor.sh`
**Configuration**: `.runner-config/failure-detection.yaml`

**Configuration Example**:
```yaml
prediction:
  model_path: "/opt/models/failure-detector.joblib"
  scaler_path: "/opt/models/feature-scaler.joblib"
  
  anomaly:
    threshold: 0.7
    contamination_rate: 0.1  # ~10% expected to be anomalies
    algorithm: "isolation_forest"
    n_estimators: 100

  features:
    enabled:
      - cpu_usage_spike
      - memory_usage_spike
      - disk_write_rate
      - network_connections
      - process_count
      - error_rate
      - duration_variance
      - exit_code_history
    
    extraction_interval: 10  # seconds
    window_size: 300  # seconds of history

  scoring:
    interval: 10  # Check every 10 seconds
    confidence_threshold: 0.65
    recompute_on_spike: true

alerting:
  webhook_url: "https://alerts.internal/webhook"
  retry_policy:
    attempts: 3
    backoff: 2
  
  slack:
    enabled: true
    channel: "#p1-alerts"
    mention_on_critical: "@p1-oncall"
  
  pagerduty:
    enabled: true
    service_id: "p1-failure-prediction"
    escalation_on_critical: true

database:
  path: "/var/lib/runner-metrics.db"
  retention_days: 30

monitoring:
  export_metrics: true
  prometheus_port: 9090
```

**Usage**:
```bash
# Start monitoring service
./failure-predictor monitor &

# Train model from historical data
./failure-predictor train ./historical-jobs.csv "2025-01-01" "2026-03-04"

# Evaluate model performance
./failure-predictor evaluate ./test-set.csv

# Get status
ps aux | grep failure-predictor
```

**Model Performance Targets**:
- Accuracy: > 90%
- Precision: > 95%
- Recall: > 85%
- False Positive Rate: < 5%
- Detection Latency: < 2 seconds

---

## Integration & System Architecture

### Component Interactions
```
Job Lifecycle:
  Job Start
    ↓
  [Failure Predictor] → Monitors for anomalies
    ↓
  [Vault Integration] → Auto-rotates credentials every 6h
    ↓
  Job Running...
    ↓
  [Anomaly Detected?] → YES → Send Alert → Trigger Cancellation
    ↓                        ↓
  NO                  [Job Cancellation Handler]
    ↓                        ↓
  Job Completes       Graceful Shutdown
    ↓                        ↓
  Clean up Credentials      Clean up State
    ↓
  Job Terminated
```

### Data Flow
```
1. OTEL Traces → Feature Extraction → Anomaly Scorer
2. Anomaly Score > Threshold → Alert Generation
3. Alert → Webhook → Job Cancellation
4. Graceful Shutdown → Checkpoint Save
5. Checkpoint → Recovery/Audit Trail
```

---

## Deployment Checklist

### Pre-Deployment (Week 1)
- [ ] All component tests passing (>90% coverage)
- [ ] Integration tests executing successfully
- [ ] Load testing completed (100+ concurrent jobs)
- [ ] Security audit passed
- [ ] Vault AppRole configuration complete
- [ ] Monitoring dashboards configured
- [ ] Alert channels tested
- [ ] Runbook documentation reviewed

### Canary Deployment (Week 2, Day 1-2)
- [ ] Pre-deployment validation passed
- [ ] Backup created
- [ ] 10% of runners selected for canary
- [ ] Components deployed to canary runners
- [ ] Monitoring active
- [ ] 24-hour observation period begins
- [ ] No critical incidents

### Gradual Rollout (Week 2, Day 3-5)
- [ ] Canary approval obtained
- [ ] 25% deployment approved
- [ ] 4-hour monitoring window passed
- [ ] 50% deployment approved
- [ ] 100% deployment approved

### Stabilization (Week 2, Day 6-7)
- [ ] 100% stability maintained
- [ ] All metrics within SLOs
- [ ] No rollback required
- [ ] Team trained
- [ ] Handoff to operations complete

### Post-Deployment (Week 3+)
- [ ] Performance baselines established
- [ ] On-call team operational
- [ ] Daily model retraining working
- [ ] Metrics trending normally

---

## Monitoring & Metrics

### Key Metrics to Track

**Job Cancellation Handler**:
- Graceful termination rate (target: >95%)
- Average grace period usage (should be <20s)
- Checkpoint recovery success rate (target: 100%)
- Resource cleanup verification

**Vault Integration**:
- Credential rotation success rate (target: 100%)
- TTL compliance (target: 100%)
- Cache hit rate (target: >80%)
- Audit log completeness

**Failure Prediction**:
- Model accuracy (target: >90%)
- False positive rate (target: <5%)
- Detection latency P95 (target: <2s)
- Alert delivery success rate (target: 100%)

**System-wide**:
- Job completion rate (target: >95%)
- Error rate (target: <1%)
- Component availability (target: 99.9%)
- Mean response latency (target: <5s)

---

## Troubleshooting Quick Reference

| Symptom | Root Cause | Resolution |
|---------|-----------|------------|
| Jobs don't terminate | Signal not handled | Verify SIGTERM handler in job wrapper |
| Credentials expire mid-job | TTL too short | Increase CREDENTIAL_TTL or reduce job duration |
| High alert rate | Threshold too low | Increase ANOMALY_THRESHOLD or retrain model |
| Model accuracy dropped | Training data stale | Retrain with recent data |
| Vault unreachable | Network/server down | Check connectivity, restart Vault |

---

## Rollback Procedures

If deployment issues detected:

```bash
# Immediate rollback
./deploy-p1-production.sh rollback

# Manual component disabling
systemctl disable job-cancellation-handler
./vault-integration cleanup
pkill -9 failure-predictor
```

---

## Support & Escalation

- **Component Owner**:
  - Job Cancellation: Platform Engineering team
  - Vault Integration: Security & Platform team
  - Failure Prediction: Data Science team

- **Escalation**: 
  - Critical: Page Platform Lead
  - High: Notify component owner
  - Warning: Document in ops log

- **Documentation**:
  - Runbooks: `docs/PHASE_P1_OPERATIONAL_RUNBOOKS.md`
  - Architecture: `docs/PHASE_P1_PLANNING.md`
  - API Reference: Component `--help` output
