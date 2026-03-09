# Phase P0 Implementation Guide: Immutable, Ephemeral, Declarative

This guide covers the complete Phase P0 implementation of the 10X platform enhancements, including immutable runner images, ephemeral workspaces, and declarative capability management.

## Phase Overview

**Duration**: 4 weeks (P0 sprint)  
**Components**: 5 major implementations  
**Dependencies**: Packer (immutable images), Terraform (infrastructure)  
**Go-live**: 100% ephemeral + immutable runner infrastructure

### Components

1. **Immutable Runner Images** (Packer)
   - Golden AMIs with Docker, tools, hardening
   - Content-addressable versioning
   - Signed artifacts with provenance tracking

2. **Ephemeral Workspace Manager**
   - Per-job isolation with copy-on-write overlays
   - Transactional cleanup with verification
   - Automatic artifact collection on failure

3. **Declarative Capability Store / CRDs**
   - Kubernetes-style Runner custom resource definitions
   - Label-based runner discovery and selection
   - Intelligent job routing with fallback strategies
   - REST API for runtime queries

4. **OpenTelemetry Tracing Integration**
   - Distributed trace collection across runners
   - Span correlation for multi-runner jobs
   - Flamegraph analysis for bottleneck identification
   - Integration with Jaeger/Grafana

5. **Fair Job Scheduler with Priority Classes**
   - Kubernetes-style QoS (system, high, normal, low, batch)
   - Per-repository quota enforcement
   - Anti-starvation aging boost
   - Preemption rules for higher priorities

6. **Drift Detection & Auto-Remediation** (Bonus)
   - Git-based source of truth validation
   - Continuous infrastructure consistency checks
   - Automatic remediation for detected deviations

---

## Quick Start

### Prerequisites
```bash
# Install required tools
apt-get install -y jq yq curl wget sqlite3 python3-pip
pip3 install pyyaml requests

# Clone or sync repository
cd /home/akushnir/self-hosted-runner
git pull origin main
```

### 1. Initialize Immutable Image Pipeline

```bash
# Build first golden image
cd packer
bash build.sh

# Expected output:
# → Building runner image v1.0.0...
# → Generated AMI: ami-0123456789abcdef0
# → Digest: sha256:abc123def456...
```

### 2. Setup Ephemeral Workspace Manager

```bash
mkdir -p /mnt/ephemeral
mkdir -p /var/log

# Create baseline snapshot
./scripts/automation/pmo/ephemeral-workspace-manager.sh setup <job-id>

# Verify
mountpoint /runner/work/_job && echo "✓ Ephemeral workspace ready"
```

### 3. Initialize Capability Store

```bash
./scripts/automation/pmo/capability-store.sh init

# Register runners
./scripts/automation/pmo/capability-store.sh register \
  ./scripts/automation/pmo/examples/runner-crd-manifests.yaml

# Start API server (background)
./scripts/automation/pmo/capability-store.sh api-server &

# Query runners
curl http://localhost:8441/api/runners | jq .
```

### 4. Configure Job Scheduler & Quotas

```bash
# Initialize queue database
./scripts/automation/pmo/fair-job-scheduler.sh init

# Load organization quotas
cp scripts/automation/pmo/examples/runner-quotas.yaml .runner-quotas.yaml
./scripts/automation/pmo/fair-job-scheduler.sh load-quotas

# Test scheduling
./scripts/automation/pmo/fair-job-scheduler.sh enqueue \
  "job-123" "my-org/my-repo" "high" 3600 ""

./scripts/automation/pmo/fair-job-scheduler.sh schedule
```

### 5. Enable OpenTelemetry Tracing

```bash
# Setup environment
./scripts/automation/pmo/otel-tracer.sh setup

# Initialize trace for a job
./scripts/automation/pmo/otel-tracer.sh init job-123 my-org/my-repo

# Emit spans
TIME_SPAN "Build Docker Image" docker build -t myapp .

# Analyze traces
./scripts/automation/pmo/otel-tracer.sh analyze ./job-123.jsonl
./scripts/automation/pmo/otel-tracer.sh flamegraph ./job-123.jsonl ./flamegraph.html
```

### 6. Enable Drift Detection

```bash
# Create configuration directory
mkdir -p .runner-config

# Copy example configuration
cp scripts/automation/pmo/examples/.runner-config/capabilities.yaml .runner-config/

# Start continuous monitoring
AUTO_REMEDIATE=true \
./scripts/automation/pmo/drift-detector.sh run &

# Check logs
tail -f /var/log/runner-drifts.log
```

---

## Architecture Integration

### Data Flow

```
GitHub Actions Job
    ↓
[Fair Job Scheduler]
    ↓
Select best runner (labels) → Capability Store
    ↓
[Ephemeral Workspace Manager]
    ├─ Create overlay mount
    ├─ Initialize workspace
    └─ Start traces
    ↓
[Runner Process]
    ├─ Execute workflow
    ├─ Emit OTEL spans
    └─ Stream metrics
    ↓
[Drift Detector] (continuous)
    └─ Validate infrastructure
    ↓
[Ephemeral Cleanup]
    ├─ Collect artifacts
    ├─ Unmount overlay
    ├─ Purge workspace
    └─ Finalize traces
```

### Component Interactions

**Capability Store → Job Scheduler**
```bash
# Scheduler queries store for runner compatibility
curl http://localhost:8441/api/route?repo=my-org/my-repo
# Response: {"runner": "gpu-runner-us-east-1"}
```

**OpenTelemetry → Capability Store**
```bash
# Traces include runner labels for cost attribution
emit_span "JobExecution" "OK" 15000 \
  --labels "runner=gpu-runner-us-east-1" \
  --cost "0.28"
```

**Drift Detector → Auto-Remediation**
```bash
# Detected drift triggers remediation
DRIFT: Package missing: docker.io
→ AUTO-REMEDIATING: apt-get install -y docker.io
→ Verified: Package installed ✓
```

---

## Configuration Files

### Runner CRDs (Capability Store)

**File**: `scripts/automation/pmo/examples/runner-crd-manifests.yaml`

```yaml
apiVersion: elevatediq.io/v1
kind: Runner
metadata:
  name: gpu-runner-us-east-1
  labels:
    gpu: "true"
    region: us-east-1
spec:
  status: online
  capabilities:
    - feature: docker
      version: "24.0"
    - feature: nvidia-cuda
      version: "12.0"
  resources:
    cpu: "4"
    memory: "16Gi"
    gpu: "1x NVIDIA T4"
  quotas:
    concurrent_jobs: 4
```

### Repository Quotas

**File**: `scripts/automation/pmo/examples/runner-quotas.yaml`

```yaml
repositories:
  my-org/platform-core:
    max_concurrent_jobs: 8
    max_vpus_per_hour: 500
    priority_class: high
  
  my-org/backend-service:
    max_concurrent_jobs: 3
    max_vpus_per_hour: 150
    priority_class: normal
```

### Drift Detection Config

**Directory**: `.runner-config/`

```
├── capabilities.yaml          Required packages & tools
├── environment.yaml            Environment variables
├── systemd.yaml               Service configuration
├── file-permissions.yaml      File access control
└── processes.yaml             Expected running processes
```

---

## Deployment Checklist

- [ ] **Week 1: Immutable Infrastructure**
  - [ ] Build first Packer image
  - [ ] Register golden AMI in Terraform
  - [ ] Launch test runner from AMI
  - [ ] Validate all tools present

- [ ] **Week 2: Ephemeral Workspaces**
  - [ ] Setup overlay mount infrastructure
  - [ ] Test ephemeral cleanup
  - [ ] Verify no artifact carryover
  - [ ] Load-test cleanup performance

- [ ] **Week 3: Declarative Routing**
  - [ ] Register all runners as CRDs
  - [ ] Configure routing rules
  - [ ] Test intelligent job selection
  - [ ] Enable scheduler

- [ ] **Week 4: Observability & Validation**
  - [ ] Deploy OpenTelemetry collector
  - [ ] Enable tracing on all jobs
  - [ ] Configure drift detection
  - [ ] Run end-to-end validation

---

## Testing & Validation

### Test 1: Immutable Image Verification
```bash
# Verify no modifications after launch
./scripts/automation/pmo/tests/test_immutable_image.sh

# Expected: All file hashes match golden image
```

### Test 2: Ephemeral Cleanup
```bash
# Run job and verify workspace purged
./scripts/automation/pmo/tests/test_ephemeral_cleanup.sh

# Expected: No leftover files in workspace
```

### Test 3: Capability Store Routing
```bash
# Test label-based runner selection
./scripts/automation/pmo/capability-store.sh find "gpu=true"

# Expected: Returns gpu-runner-us-east-1
```

### Test 4: Fair Scheduling
```bash
# Verify quota enforcement
./scripts/automation/pmo/tests/test_fair_scheduling.sh

# Expected: Jobs blocked when quota exceeded
```

### Test 5: Drift Detection
```bash
# Introduce drift and verify detection
rm /usr/bin/jq  # Simulate missing package

./scripts/automation/pmo/drift-detector.sh check

# Expected: DRIFT detected and auto-remediated
```

---

## Monitoring & Alerts

### Key Metrics

```
runner_image_age_days              - Golden AMI freshness
ephemeral_workspace_cleanup_time   - Cleanup latency (target: <5s)
capability_store_api_latency_ms    - Router response time (target: <100ms)
job_queue_depth_total              - Jobs waiting for runner
job_starvation_hours               - Longest job waiting (alert: >2h)
infrastructure_drift_count         - Drifts detected (alert: >5)
```

### Alert Rules

```yaml
# prometheus/alerts.yml additions
- alert: JobStarvation
  expr: max(job_queue_wait_secs) > 7200
  for: 5m
  annotations:
    summary: "Jobs waiting > 2 hours in queue"

- alert: InfraDriftDetected
  expr: infrastructure_drift_count > 5
  for: 1m
  annotations:
    summary: "Multiple infrastructure drifts detected"

- alert: EphemeralCleanupFailed
  expr: ephemeral_cleanup_errors_total > 0
  for: 1m
  annotations:
    summary: "Workspace cleanup failures"
```

---

## Troubleshooting

### Issue: "No suitable runner found"

**Cause**: All runners fully utilized or no matching labels  
**Solution**:
```bash
# Check runner capacity
./scripts/automation/pmo/capability-store.sh status

# Add more runners or adjust quotas
vim .runner-quotas.yaml
./scripts/automation/pmo/fair-job-scheduler.sh load-quotas
```

### Issue: "Ephemeral workspace mount failed"

**Cause**: Overlay filesystem not available  
**Solution**:
```bash
# Check kernel support for overlay
grep -i overlay /proc/filesystems

# Use bind mount fallback (performance degraded)
AUTO_FALLBACK=true ./scripts/automation/pmo/ephemeral-workspace-manager.sh setup <job-id>
```

### Issue: "Drift detection cascading"

**Cause**: Auto-remediation causing repeated drifts  
**Solution**:
```bash
# Disable auto-remediation temporarily
AUTO_REMEDIATE=false ./scripts/automation/pmo/drift-detector.sh check

# Review detected drifts
tail -50 /var/log/runner-drifts.log

# Fix root cause in config
git -C .runner-config commit -am "Fix root cause of drifts"
git push
```

---

## Performance Tuning

### Ephemeral Workspace Optimization
```bash
# Enable asynchronous cleanup for large artifacts
ASYNC_CLEANUP=true \
CLEANUP_TIMEOUT_SECS=60 \
./scripts/automation/pmo/ephemeral-workspace-manager.sh cleanup

# Monitor cleanup performance
grep "cleanup_secs" /var/log/runner-*.jsonl | jq '.[1]' | \
  awk '{sum+=$NF; count++} END {print "avg:", sum/count}'
```

### Scheduler Optimization
```bash
# Tune scheduling interval for load
SCHEDULER_INTERVAL=2 ./scripts/automation/pmo/fair-job-scheduler.sh run

# Monitor queue depth evolution
watch "sqlite3 /var/lib/runner-queue.db 'SELECT COUNT(*) FROM job_queue WHERE status=\"queued\";'"
```

### Trace Sampling
```bash
# For high-throughput environments, reduce sampling
TRACE_SAMPLE_RATE=0.01 \
./scripts/automation/pmo/otel-tracer.sh setup

# Still capture slow traces (>1000ms)
MIN_TRACE_DURATION_MS=1000
```

---

## Next Steps (Phase P1)

After completing Phase P0, the next phase (P1, 6 weeks) will add:

- **Graceful Job Cancellation**: SIGTERM handlers, process cleanup
- **Secrets Rotation**: Vault integration, 6-hour cycle
- **ML-Based Failure Prediction**: Anomaly detection for likely failures

See [ENHANCEMENTS_10X.md](archive/completion-reports/ENHANCEMENTS_10X.md) for full Phase P1-P3 plans.

---

## Support & Questions

For issues or questions:
1. Check [Troubleshooting](#troubleshooting) section
2. Review logs in `/var/log/runner-*.log`
3. Generate drift report: `./scripts/automation/pmo/drift-detector.sh report`
4. Check GitHub repository issues

---

Generated: 2024-03-04  
Last Updated: Phase P0 Implementation Guide v1.0
