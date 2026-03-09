# Phase P0 Quick Reference Card

## 🚀 One-Liner Quick Start

```bash
# Full Phase P0 setup (development/testing)
cd /home/akushnir/self-hosted-runner && \
  chmod +x scripts/automation/pmo/*.sh && \
  mkdir -p /mnt/ephemeral /var/lib/runner-queue && \
  scripts/automation/pmo/ephemeral-workspace-manager.sh setup test-job && \
  scripts/automation/pmo/capability-store.sh init && \
  scripts/automation/pmo/capability-store.sh register scripts/automation/pmo/examples/runner-crd-manifests.yaml && \
  scripts/automation/pmo/fair-job-scheduler.sh init && \
  scripts/automation/pmo/fair-job-scheduler.sh load-quotas && \
  echo "✅ Phase P0 initialized!"
```

---

## 📋 Component Commands at a Glance

### Ephemeral Workspace Manager
```bash
# Setup: Create immutable overlay for job
./ephemeral-workspace-manager.sh setup <job-id>

# Cleanup: Purge with verification (trap on exit)
./ephemeral-workspace-manager.sh cleanup

# Full workflow:
JOB_ID="job-$(date +%s)"
./ephemeral-workspace-manager.sh setup "$JOB_ID"
# ... run job ...
# Auto-cleanup on exit (trap registered)
```

### Capability Store (Runner Registry)
```bash
# Init: Create store database
./capability-store.sh init

# Register: Add runner from YAML manifest
./capability-store.sh register ./runner-crd-manifests.yaml

# Find: Discover runners by labels
./capability-store.sh find "gpu=true,region=us-east-1"

# Route: Select best runner for job
./capability-store.sh route "my-org/my-repo"

# API Server: Start HTTP API (port 8441)
./capability-store.sh api-server &
curl http://localhost:8441/api/runners | jq .
```

### Fair Job Scheduler
```bash
# Init: Create queue database
./fair-job-scheduler.sh init

# Load Quotas: Apply org policies
./fair-job-scheduler.sh load-quotas

# Enqueue: Add job (priority: system|high|normal|low|batch)
./fair-job-scheduler.sh enqueue <job-id> <repo> <priority> <duration> [labels]

# Schedule: Select next job to run
JOB=$(./fair-job-scheduler.sh schedule)

# Complete: Mark done and free quota
./fair-job-scheduler.sh complete <job-id>

# Status: View queue depth, quotas, runners
./fair-job-scheduler.sh status
```

### OpenTelemetry Tracer
```bash
# Init: Start new trace for job
./otel-tracer.sh init <job-id> <repo>

# Emit: Record a span manually
./otel-tracer.sh emit "BuildStep" OK 5000

# Time: Execute with automatic span
./otel-tracer.sh time "RunTests" pytest tests/

# Instrument: Add tracing to workflow
./otel-tracer.sh instrument-workflow .github/workflows/ci.yml

# Analyze: Find slow spans
./otel-tracer.sh analyze ./job-123.jsonl

# Flamegraph: Visualize call stacks
./otel-tracer.sh flamegraph ./job-123.jsonl ./output.html
```

### Drift Detector
```bash
# Check: Run single drift detection cycle
./drift-detector.sh check

# Run: Start continuous monitoring
AUTO_REMEDIATE=true ./drift-detector.sh run &

# Report: Generate compliance report
./drift-detector.sh report

# Log: View all detected drifts
tail -f /var/log/runner-drifts.log
```

---

## 🔧 Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `runner-crd-manifests.yaml` | Runner definitions (GPU, standard, memory) | `scripts/automation/pmo/examples/` |
| `runner-quotas.yaml` | Repository quotas and priorities | `scripts/automation/pmo/examples/` |
| `capabilities.yaml` | Expected system packages and tools | `scripts/automation/pmo/examples/.runner-config/` |
| `.runner-config/` | Drift detection source of truth (Git-based) | Project root |

---

## 📊 Architecture Diagrams

### Job Flow with Phase P0
```
GitHub Job
    ↓
[Fair Scheduler] ← [Runner CRDs] (capability store)
    ↓ (select best runner)
[Ephemeral Setup] ← [OTEL Tracer] (emit trace start)
    ↓ (create overlay)
[Executive] ← [Health Monitor] (verify running)
    ↓ (run workflow)
[Drift Detector] ← [Auto-Remediate] (validate config)
    ↓ (continuous checks)
[Ephemeral Cleanup] ← [OTEL Tracer] (emit trace end)
    ↓ (transactional purge)
[Complete] ← [Scheduler] (free quota)
    ↓
Job Output
```

### Data Model
```
Runner CRD (Capability Store)
├── metadata.name: gpu-runner-us-east-1
├── metadata.labels: {gpu: true, region: us-east-1}
├── spec.capabilities: [docker, cuda, pytorch]
├── spec.resources: {cpu: 4, memory: 16Gi, gpu: 1}
└── spec.quotas: {concurrent_jobs: 4}

Repository Quota
├── max_concurrent_jobs: 8
├── max_vpus_per_hour: 500
├── priority_class: high
└── reserved_slots: 2

Job Queue Entry
├── id: job-123456
├── repository: my-org/my-repo
├── priority_class: high
├── status: queued|scheduled|completed
└── created_at: timestamp
```

---

## 🎯 Key Metrics to Monitor

### Performance
```bash
# Workspace overlay creation time
grep "overlay mount" /var/log/runner-*.log | jq '.duration_ms'

# Runner routing latency
curl -w "%{time_total}\n" http://localhost:8441/api/runners

# Scheduler decision time
grep "schedule_decision_ms" /var/log/runner-*.jsonl | jq '.pipeline.schedule_decision_ms'
```

### Utilization
```bash
# Queue depth
sqlite3 /var/lib/runner-queue.db \
  "SELECT COUNT(*) FROM job_queue WHERE status='queued';"

# Per-repo usage
sqlite3 /var/lib/runner-queue.db \
  "SELECT repository, COUNT(*) FROM job_queue GROUP BY repository;"

# Runner occupancy
sqlite3 /var/lib/runner-queue.db \
  "SELECT runner_id, available_slots FROM runner_capacity;"
```

### Health
```bash
# Infrastructure drifts detected
grep "DRIFT detected" /var/log/runner-drifts.log | wc -l

# Auto-remediation success rate
grep "AUTO-REMEDIATING" /var/log/runner-drifts.log | \
  awk '{success=(\$0 ~ /✓/) ? success+1 : success} END {print success}'

# Job starvation (jobs waiting >1 hour)
sqlite3 /var/lib/runner-queue.db \
  "SELECT COUNT(*) FROM job_queue WHERE status='queued' AND (strftime('%s','now') - created_at) > 3600;"
```

---

## 🐛 Common Troubleshooting

| Issue | Check | Fix |
|-------|-------|-----|
| "No suitable runner found" | `./capability-store.sh find "gpu=true"` | Register more runners or adjust labels |
| Queue not moving | `./fair-job-scheduler.sh status` | Check quotas, complete old jobs |
| Workspace cleanup fails | Check `/mnt/ephemeral` mount | Re-mount or use bind mount fallback |
| Traces not appearing | Check OTEL env vars | Run `./otel-tracer.sh setup` |
| Drift escalation | `tail /var/log/runner-drifts.log` | Disable auto-remediate, fix root cause |
| API 404 errors | `curl http://localhost:8441/api/runners` | Restart capability-store api-server |

---

## 📚 Documentation Links

| Document | Purpose | Read Time |
|----------|---------|-----------|
| [PHASE_P0_IMPLEMENTATION.md](PHASE_P0_IMPLEMENTATION.md) | Complete implementation guide | 30 min |
| [PHASE_P0_COMPLETION_SUMMARY.md](PHASE_P0_COMPLETION_SUMMARY.md) | What was built and why | 20 min |
| [ENHANCEMENTS_10X.md](archive/completion-reports/ENHANCEMENTS_10X.md) | Full 10X vision (P0-P3) | 45 min |
| [README.md](../self_healing/README.md) | Project overview | 10 min |

---

## 🚀 Deployment Sequence

1. **Day 1**: Test locally
   ```bash
   cd /home/akushnir/self-hosted-runner
   ./scripts/automation/pmo/tests/test_ephemeral_cleanup.sh
   ./scripts/automation/pmo/tests/test_fair_scheduling.sh
   ```

2. **Day 2**: Deploy to staging
   ```bash
   # Use Terraform to provision test runners
   cd terraform
   terraform apply -var environment=staging
   ```

3. **Day 3**: Enable read-only mode
   ```bash
   # Monitor without making changes
   AUTO_REMEDIATE=false ./scripts/automation/pmo/drift-detector.sh run
   ```

4. **Day 4**: Enable with caution
   ```bash
   # Enable one component at a time
   ./scripts/automation/pmo/fair-job-scheduler.sh run
   # Monitor for 24h
   # Enable next component
   ```

5. **Day 5**: Full deployment
   ```bash
   # All components enabled
   AUTO_REMEDIATE=true ./scripts/automation/pmo/drift-detector.sh run &
   ./scripts/automation/pmo/capability-store.sh api-server &
   ./scripts/automation/pmo/fair-job-scheduler.sh run &
   ```

---

## 💡 Tips & Tricks

### Enable detailed logging
```bash
export LOG_LEVEL=debug
export LOG_FILE=/tmp/runner-debug.log
./capability-store.sh init  # Will log to file
```

### Dry-run mode for destructive ops
```bash
# Test cleanup without actually removing
CLEANUP_DRY_RUN=true ./ephemeral-workspace-manager.sh cleanup
```

### Inspect job traces in realtime
```bash
# Stream traces as they arrive
tail -f $(ls -t /var/log/traces/*.jsonl | head -1) | jq '.resourceSpans[].scopeSpans[].spans[].name'
```

### Check scheduler decisions
```bash
# What job is scheduler picking?
sqlite3 -header /var/lib/runner-queue.db \
  "SELECT id, repository, priority_class, created_at FROM job_queue WHERE status='queued' ORDER BY (1000/priority_class) DESC LIMIT 5;"
```

### Monitor runner health
```bash
# Real-time runner availability
watch -n5 "sqlite3 /var/lib/runner-queue.db \"SELECT runner_id, available_slots FROM runner_capacity WHERE available_slots > 0;\""
```

---

## ✅ Phase P0 Checklist

Setup:
- [ ] All scripts are executable (`chmod +x *.sh`)
- [ ] Required directories exist `/mnt/ephemeral`, `/var/lib/runner-queue`
- [ ] Database files created (SQLite)
- [ ] Example configs copied and reviewed

Configuration:
- [ ] Runner CRDs registered via capability store
- [ ] Repository quotas loaded
- [ ] Drift detection config committed to Git

Deployment:
- [ ] Components tested locally
- [ ] Monitoring configured (Prometheus)
- [ ] Alerts set for critical metrics
- [ ] Runbooks prepared for on-call

---

## 🎓 Learning Resources

### Key Concepts
- **CoW Overlay Filesystem**: InstantVM provisioning technique
- **CRD Pattern**: Kubernetes declarative specs in Git
- **Distributed Tracing**: W3C trace context standard
- **Fair Scheduling**: Deficit round-robin with anti-starvation
- **GitOps**: Infrastructure as code, Git as source of truth

### Commands to Practice
```bash
# Practice workflow
for i in {1..5}; do
  JOB="job-$i"
  echo "Testing $JOB..."
  ./capability-store.sh find "gpu=true"
  ./fair-job-scheduler.sh enqueue "$JOB" "test-repo" "normal"
  ./fair-job-scheduler.sh schedule
done
./fair-job-scheduler.sh status
```

---

**Last Updated**: March 4, 2024  
**Phase**: P0 ✅ **COMPLETE**  
**Next**: P1 (6 weeks) - Graceful cancellation, secrets rotation, ML prediction  
**Questions?** See [PHASE_P0_IMPLEMENTATION.md](PHASE_P0_IMPLEMENTATION.md#support--questions) troubleshooting section
