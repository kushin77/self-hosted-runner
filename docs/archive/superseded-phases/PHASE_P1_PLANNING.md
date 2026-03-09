# Phase P1 Planning & Implementation Guide

**Status**: 📋 Planning Phase | **Target Duration**: 6 weeks | **Start Date**: Week after Phase P0  
**Focus**: Graceful cancellation, secrets rotation, failure prediction

---

## Phase P1 Overview

Phase P1 builds on Phase P0's immutable, ephemeral infrastructure by adding:

1. **Graceful Job Cancellation** (3 weeks)
   - SIGTERM handlers in job wrapper
   - Process tree cleanup with escalation
   - Checkpoint/state saving
   - Timeout enforcement

2. **Secrets Rotation Integration** (2 weeks)
   - Vault-based credential management
   - 6-hour rotation cycle
   - Automatic runner credential refresh
   - Audit logging

3. **ML-Based Failure Prediction** (1 week scaffolding, 2 weeks model training)
   - Anomaly detection model
   - Real-time scoring
   - Proactive recommendations
   - Historical analysis

---

## Component 1: Graceful Job Cancellation

### Problem Statement
- Jobs terminated abruptly leave processes running
- No cleanup of temporary resources
- Lost work/context when cancelled
- Difficulty in job state recovery

### Solution Architecture
```
SIGTERM Signal
    ↓
[Checkpoint Handler] → Save job state
    ↓
[Graceful Termination]
├─ Phase 1: SIGTERM to process group (30s grace)
├─ Phase 2: SIGKILL if grace expires (10s)
└─ Phase 3: Verify cleanup
    ↓
[Resource Cleanup]
├─ Close file descriptors
├─ Flush buffers
└─ Update status
    ↓
Exit (code 143)
```

### Implementation Plan

**Week P1-1: Foundation**
- [ ] Implement signal handlers (SIGTERM, SIGINT)
- [ ] Create process tree tracking
- [ ] Add checkpoint mechanism
- [ ] Basic CLI interface

**Week P1-2: Integration**
- [ ] GitHub Actions workflow integration
- [ ] Status reporting to GitHub API
- [ ] Integration with health monitor
- [ ] Systemd service wrapper

**Week P1-3: Testing & Hardening**
- [ ] Comprehensive test suite
- [ ] Load testing (1000+ concurrent jobs)
- [ ] Failure scenarios
- [ ] Documentation & runbooks

### Testing Criteria
- ✓ All child processes terminate within grace period
- ✓ Checkpoints successfully save and restore
- ✓ No resource leaks on termination
- ✓ GitHub Actions status updates correctly
- ✓ Health monitor verifies cleanup

### Configuration
```yaml
# .github/workflows/job-config.yml
job-cancellation:
  enabled: true
  grace-period-secs: 30
  timeout-secs: 3600
  checkpoint-dir: /tmp/job-checkpoints
  auto-checkpoint: true
  alert-on-timeout: true
```

---

## Component 2: Secrets Rotation Integration

### Problem Statement
- Long-lived credentials increase breach risk
- Manual rotation is error-prone
- No audit trail for secret access
- Orphaned credentials when runners decommissioned

### Solution Architecture
```
Vault Server
    ↓
[Credential Request] (at job start)
    ↓
[TTL Enforcement] (max 6 hours)
    ↓
[Automatic Refresh]
├─ 5-min before expiry
├─ Fetch new credentials
└─ Update environment
    ↓
[Audit Trail]
├─ Who: service account
├─ What: token rotation
├─ When: timestamp
└─ Where: runner hostname
    ↓
[Cleanup] (at job end)
└─ Revoke used credentials
```

### Implementation Plan

**Week P1-2: Vault Integration**
- [ ] Vault CLI setup and authentication
- [ ] AppRole provisioning for runners
- [ ] Policy creation for secret access
- [ ] Python client for credential management

**Week P1-3: Rotation Daemon**
- [ ] Background rotation service
- [ ] TTL monitoring
- [ ] Graceful refresh without job interruption
- [ ] Fallback to manual rotation

**Week P1-4: Testing & Deployment**
- [ ] Integration tests with mock Vault
- [ ] Load testing (100+ concurrent rotations)
- [ ] Failure scenarios (Vault unavailable)
- [ ] Audit logging verification

### Vault Policy Example
```hcl
path "secret/data/runners/*" {
  capabilities = ["read", "list"]
}

path "auth/approle/role/runner-role/secret-id" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}
```

### Testing Criteria
- ✓ Credentials rotate every 6 hours
- ✓ Old credentials revoked immediately
- ✓ Job continues without interruption
- ✓ Audit log complete and immutable
- ✓ Fallback mechanism works if Vault offline

### Configuration
```yaml
# .runner-config/vault.yaml
vault:
  server-url: "https://vault.internal:8200"
  auth-method: "approle"
  role-id: "${VAULT_ROLE_ID}"
  secret-id-path: "/run/vault/.secret"
  rotation-interval-secs: 21600  # 6 hours
  pre-rotation-warning-secs: 300  # 5 minutes
  ttl: 21600
  max-ttl: 86400
  audit-backend: "file"
  audit-path: "/var/log/vault-audit"
```

---

## Component 3: ML-Based Failure Prediction

### Problem Statement
- Failures discovered after job completes
- No early warning system
- Resource wasted on doomed jobs
- No pattern recognition across jobs

### Solution Architecture
```
Historical Job Data (Phase P0 traces)
    ↓
[Feature Engineering]
├─ Resource anomalies
├─ Timing patterns
├─ Error frequency
└─ Environmental factors
    ↓
[Model Training] (Isolation Forest)
├─ Normal behavior baseline
├─ Anomaly thresholds
└─ Feature importance
    ↓
[Real-time Scoring]
├─ Running job metrics
├─ Compute anomaly score
└─ Generate alert (>0.7 threshold)
    ↓
[Action]
├─ Notify runner operator
├─ Log prediction
├─ Collect for model refinement
└─ Optional: preemptive cancellation
```

### Implementation Plan

**Week P1-5: Data Pipeline**
- [ ] Extract Phase P0 OTEL traces
- [ ] Feature engineering scripts
- [ ] Data validation and cleaning
- [ ] Metric normalization

**Week P1-6: Model Development**
- [ ] Isolation Forest implementation
- [ ] Hyperparameter tuning
- [ ] Validation dataset preparation
- [ ] Model persistence (pickle/ONNX)

**Week P1-7: Deployment**
- [ ] Real-time scoring service
- [ ] Integration with runner monitoring
- [ ] Alert generation
- [ ] Model retraining pipeline

### Feature Set (Example)
```python
features = {
  "cpu_usage_spike": metrics.cpu_max / metrics.cpu_avg,
  "memory_usage_spike": metrics.mem_max / metrics.mem_avg,
  "disk_write_rate": metrics.disk_mb_per_sec,
  "network_connections": metrics.tcp_connections_count,
  "process_count": metrics.process_count,
  "error_rate": metrics.errors / metrics.total_events,
  "duration_variance": current_duration / expected_duration,
  "exit_code_history": historical_success_rate.for_repo,
}

anomaly_score = model.decision_function([features])  # Isolation Forest
is_anomalous = anomaly_score > 0.7
```

### Testing Criteria
- ✓ Model detects injected failures with >90% accuracy
- ✓ False positive rate <5%
- ✓ Real-time scoring latency <100ms
- ✓ Graceful degradation if model unavailable
- ✓ Audit trail of all predictions

### Configuration
```yaml
# .runner-config/failure-prediction.yaml
prediction:
  model-path: /opt/models/failure-detector.joblib
  model-version: "1.0.0"
  anomaly-threshold: 0.7
  scoring-interval-secs: 10
  retraining-frequency: "weekly"
  grace-period-before-alert-secs: 60
  actions:
    alert-operator: true
    log-to-monitoring: true
    optional-preemption: false
```

---

## Deployment Roadmap

```
Week 1-3    Phase P1.1: Graceful Cancellation
  ├─ Develop & test cancellation handler
  ├─ Integrate with runner
  └─ Deploy to staging
  
Week 2-4    Phase P1.2: Secrets Rotation
  ├─ Setup Vault + policies
  ├─ Implement rotation daemon
  └─ Deploy to staging
  
Week 5-7    Phase P1.3: Failure Prediction
  ├─ Extract & process historical data
  ├─ Train ML model
  ├─ Deploy scoring service
  └─ Monitor predictions
  
Week 8     Phase P1 Release
  ├─ All components to production
  ├─ Full observability enabled
  └─ Documentation complete
```

---

## Success Metrics (Phase P1)

| Metric | Target | Measurement |
|--------|--------|-------------|
| Job Cancellation Latency | <500ms | Time to SIGTERM handler response |
| Graceful Termination Rate | >95% | Jobs cleaned up within grace period |
| Secrets Rotation Success | 100% | Zero failed rotations over 1 month |
| Credential TTL Compliance | 100% | All credentials <6 hours old |
| Failure Prediction Accuracy | >90% | True positive rate |
| False Positive Rate | <5% | Alerted failures that don't occur |
| Mean Time To Prevention | <5 min | Time from alert to action |

---

## Integration with Phase P0

Phase P1 builds on Phase P0 components:

```
Phase P0                          Phase P1
─────────────────────────────────────────────
Ephemeral Workspace      →    Cancellation cleans up workspace
Capability Store         →    Uses runner labels for scoring context
OTEL Tracing             →    Provides features for ML model
Fair Scheduler           →    Preemption based on predictions
Drift Detector           →    Verifies secrets not leaked
```

---

## Approval & Sign-off

- [ ] Architecture approved by platform team
- [ ] Resource allocation approved
- [ ] Timeline confirmed with stakeholders
- [ ] Success metrics agreed upon
- [ ] Rollback plan reviewed
- [ ] Production readiness checklist signed off

---

## Next Steps

1. **Immediately (This Week)**
   - [ ] Create GitHub issues for P1 components
   - [ ] Assign owners to each component
   - [ ] Setup development environment

2. **Week 1**
   - [ ] Kickoff meeting with team
   - [ ] Design reviews for each component
   - [ ] Development starts

3. **Ongoing**
   - [ ] Weekly status updates
   - [ ] Integration testing at component completion
   - [ ] Documentation written in parallel

---

**Document Version**: 1.0  
**Date**: March 4, 2026  
**Phase**: P1 Planning (Pre-implementation)  
**Status**: ✏️ **READY FOR APPROVAL**

For detailed Phase P0-P4 roadmap, see [ENHANCEMENTS_10X.md](archive/completion-reports/ENHANCEMENTS_10X.md)
