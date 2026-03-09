# Ephemeral Runner Lifecycle & Safe Termination Runbook

## Overview

This runbook provides operational guidance for managing ephemeral runner lifecycle using dynamic TTL policies and safe termination procedures. The system automatically assigns TTL (Time-To-Live) based on job complexity and manages graceful drain/reap operations.

**Key Concepts:**
- **Dynamic TTL:** TTL assigned at job start based on job type and resource characteristics
- **Graceful Drain:** In-progress jobs complete; state is cleaned; runner shuts down safely
- **Safe Reap:** Automated termination when TTL expires and runner is idle
- **Audit Trail:** Immutable logs of all lifecycle events for compliance and debugging

---

## Table of Contents

- [Quick Start](#quick-start)
- [TTL Policy System](#ttl-policy-system)
- [Assigning TTL](#assigning-ttl)
- [Graceful Drain](#graceful-drain)
- [Safe Reap](#safe-reap)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)
- [FAQ](#faq)

---

## Quick Start

### View Current Runner Status

```bash
python3 scripts/ephemeral-lifecycle-controller.py info
```

Output:
```
======================================================================
EPHEMERAL RUNNER LIFECYCLE STATUS
======================================================================

Runner:           ubuntu-runner-1
Home:             /opt/runners/runner-1
Job:              compile-backend

TTL Configuration:
  Assigned At:    2026-03-09T15:30:45Z
  TTL (seconds):  3600
  Policy:         build
  Job Type:       build
  Extensions:     0

Reap Safety:
  TTL Expired:         False
  No in-progress jobs: True
  Safe to Reap:        False

======================================================================
```

### Assign TTL to a Job

```bash
python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
  --job-type build \
  --labels production \
  --duration 1800
```

Output:
```
✓ TTL assigned: 3600s (policy: build)
```

### Check if Safe to Reap

```bash
python3 scripts/ephemeral-lifecycle-controller.py check-reap
```

Output:
```
Safe to reap: True
Checks: {
  'ttl_expired': True,
  'no_in_progress_jobs': True,
  'no_recent_heartbeat': True,
  'safe_to_reap': True
}
```

---

## TTL Policy System

### Policy Hierarchy

Jobs are matched to policies based on job type, labels, and resource characteristics. The first matching policy is used.

**Predefined Policies:**

| Policy | Job Types | Base TTL | Max TTL | Use Case |
|--------|-----------|----------|---------|----------|
| `quick-test` | `test`, `lint`, `check` | 10m | 15m | Unit tests, linting |
| `build` | `build`, `compile` | 30m | 1h | Build operations |
| `integration-test` | `integration`, `e2e` | 1h | 2h | Integration tests |
| `deploy` | `deploy`, `deploy:prod` | 2h | 8h | Deployments |
| `infrastructure` | `terraform`, `provision` | 4h | 24h | Long-running infra |
| (default) | Any unmatched | 30m | - | Fallback |

### Telemetry Adjustments

TTL is automatically adjusted based on resource utilization observed during job execution:

**CPU Utilization Multipliers:**
- High (>80%): 1.5x TTL increase
- Medium (50-80%): 1.2x TTL increase
- Low (<50%): 0.8x TTL decrease

**Memory Utilization Multipliers:**
- High (>80%): 1.3x TTL increase
- Medium (50-80%): 1.0x (no change)
- Low (<50%): 0.9x TTL decrease

**Example:** A build job with high CPU usage:
```
Base TTL: 30 minutes
Complexity multiplier: 1.5
CPU adjustment: 1.5x (high)
Final TTL: 30min * 1.5 * 1.5 = 67.5 min (capped at policy max of 1h)
Result: 60 minutes
```

### Custom Policy Configuration

Edit `config/ttl-policies.yaml` to customize policies:

```yaml
policies:
  - name: "my-custom-job"
    description: "Custom long-running jobs"
    filters:
      job_type:
        - "my_job_type"
      labels:
        - "custom"
      max_duration: 14400
    ttl_config:
      base_ttl: 3600          # 1 hour
      max_ttl: 14400          # 4 hours max
      complexity_multiplier: 2.0
    drain_policy:
      allow_graceful_drain: true
      drain_grace_period: 300
      allow_in_progress_jobs: true
      timeout: 1200
```

After editing, restart runners or reload policies:

```bash
# Relaunch runners to pick up new policies
ansible-playbook -i inventory/runners deploy-ephemeral-runners.yml
```

---

## Assigning TTL

### Automatic Assignment at Job Start

The lifecycle controller automatically assigns TTL when a job starts. Add this to your GitHub Actions workflow:

```yaml
jobs:
  my-build:
    runs-on: self-hosted-ephemeral
    steps:
      - name: Assign TTL based on job type
        id: ttl
        run: |
          python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
            --job-type build \
            --labels ${{ join(matrix.*, ',') }} \
            --duration 1800 \
            --cpu-util 0.7 \
            --mem-util 0.6
      
      - name: Build application
        run: make build
```

### Manual TTL Assignment

For one-off jobs or testing:

```bash
# Quick test - 10 minute TTL
python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
  --job-type test

# Build with specific duration hint
python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
  --job-type build \
  --duration 1800 \
  --labels production,critical

# With telemetry (if collected)
python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
  --job-type integration-test \
  --cpu-util 0.85 \
  --mem-util 0.72
```

### Extending TTL

To extend TTL for a running job (up to `max_extensions` limit):

```bash
# The system tracks extensions; manually extending requires:
# 1. Check current state
python3 scripts/ephemeral-lifecycle-controller.py info

# 2. If close to expiry, apply for extension
# (Requires admin API call or manual workflow update)
curl -X POST https://api.github.com/repos/kushin77/self-hosted-runner/dispatches \
  -H "Authorization: token $GITHUB_TOKEN" \
  -d '{"event_type":"extend-runner-ttl"}'
```

---

## Graceful Drain

### What is Graceful Drain?

Graceful drain is the controlled termination of a runner while respecting in-progress jobs. Steps:

1. **Notify** workflow context about impending termination
2. **Set offline** in GitHub runner pool (no new jobs assigned)
3. **Wait** for in-progress jobs to complete (up to timeout)
4. **Upload** logs and artifacts
5. **Cleanup** ephemeral state
6. **Shutdown** runner

### Initiating Graceful Drain

**Automatic (at TTL expiry):**
```bash
# Cron job runs every 5 minutes to check for expired runners
0,5,10,15,20,25,30,35,40,45,50,55 * * * * \
  python3 scripts/ephemeral-lifecycle-controller.py drain \
  --strategy graceful --timeout 300
```

**Manual:**
```bash
# Start graceful drain with 5-minute timeout
python3 scripts/ephemeral-lifecycle-controller.py drain \
  --strategy graceful \
  --timeout 300

# Forceful fallback if graceful times out
python3 scripts/ephemeral-lifecycle-controller.py drain \
  --strategy forceful \
  --timeout 60
```

### Graceful Drain Timeline

```
T+0:00 - Graceful drain initiated
  └─ Notify workflow context
  └─ Set runner offline in GitHub
  └─ Wait for running processes to finish

T+4:55 - Final minute: check for stragglers
  └─ If processes still running: forceful termination

T+5:00 - Cleanup
  └─ Upload logs and artifacts
  └─ Cleanup ephemeral state (remove /tmp, /work, caches)
  └─ Export metrics and audit log

T+5:30 - Shutdown
  └─ Runner instance terminated
  └─ Cloud resources cleaned up
```

### Graceful Drain with In-Progress Jobs

If jobs are running during drain initiation:

```
Runner has 2 running jobs (5min and 8min remaining)
Graceful drain initiated with 10min timeout

Lifecycle:
T+0min  → Notify jobs, set offline
T+5min  → First job completes, continues waiting
T+8min  → Second job completes
T+8:30  → Upload logs, cleanup
T+9:00  → Ready for shutdown

Result: ✓ Both jobs completed successfully
```

---

## Safe Reap

### What is Safe Reap?

Safe reap automatically terminates runners when:
- TTL has expired
- No in-progress jobs are running
- No recent heartbeat detected (runner idle)

### Automated Reap Workflow

```
T+TTL  → TTL Expiry detected
  ↓
Check Safety:
  ✓ TTL expired?        → YES
  ✓ No running jobs?    → YES
  ✓ No recent activity? → YES
  ↓
All checks pass → Execute reap
  ↓
Cleanup → Terminate instance
```

### Manual Reap Operations

**Check if safe to reap:**
```bash
python3 scripts/ephemeral-lifecycle-controller.py check-reap
```

**Execute safe reap:**
```bash
python3 scripts/ephemeral-lifecycle-controller.py reap
```

**Force reap (bypass safety checks):**
```bash
python3 scripts/ephemeral-lifecycle-controller.py reap --force
```

### Reap Safety Verification

Before reaping, the system verifies:

| Check | Description | Importance |
|-------|-------------|-----------|
| TTL Expired | Current time > assigned_at + ttl_seconds | **CRITICAL** |
| No In-Progress Jobs | 0 running processes detected | **CRITICAL** |
| No Recent Heartbeat | No runner activity for 5+ minutes | **HIGH** |
| Offline Status | Runner marked offline in GitHub | **MEDIUM** |

If any CRITICAL check fails, reap is blocked unless `--force` is used.

---

## Monitoring & Observability

### Metrics to Track

**Key Metrics:**
- `ttl_assigned` - TTL value at runner startup
- `ttl_remaining` - Current remaining TTL
- `ttl_extensions` - Number of TTL extensions
- `drain_duration` - Time taken to drain (seconds)
- `drain_success_rate` - % of graceful drains that succeeded
- `reap_latency` - Time from TTL expiry to actual reap

### Audit Trail

All lifecycle events are logged immutably to `audit-logs/`:

```bash
# View audit log for today
cat /tmp/audit-logs/audit-20260309.jsonl | jq .

# Example entry:
{
  "timestamp": "2026-03-09T15:35:12Z",
  "event": "ttl_assigned",
  "runner_id": "ubuntu-runner-1",
  "job_id": "compile-backend",
  "audit_id": "a1b2c3d4-e5f6-7890-abcd",
  "details": {
    "ttl_seconds": 3600,
    "policy_name": "build",
    "job_type": "build"
  }
}
```

### Monitoring Dashboard

Key metrics to visualize:

```promql
# Average TTL assigned
avg(ttl_assigned)

# TTL extensions distribution
histogram_quantile(0.95, rate(ttl_extensions[5m]))

# Graceful drain success rate
rate(drain_success_total[5m]) / rate(drain_total[5m])

# Average drain duration
avg(drain_duration_seconds)

# Runners awaiting reap
count(runner_status == "expired_ready_reap")
```

### Alerting Rules

**Critical Alerts:**

1. Graceful drain success rate < 90%
   ```promql
   (rate(drain_success_total[1h]) / rate(drain_total[1h])) < 0.9
   ```

2. Reap latency > 10 minutes
   ```promql
   histogram_quantile(0.95, rate(reap_latency_seconds[1h])) > 600
   ```

3. TTL < 5 minutes remaining
   ```promql
   ttl_remaining < 300
   ```

---

## Troubleshooting

### Runner Not Assigned TTL

**Symptoms:** `info` command shows no TTL configuration

**Diagnosis:**
```bash
# Check state file exists
ls -la /tmp/runner-ttl-state.json

# Check recent logs
grep "Assigning TTL" /tmp/runner-*.log

# Check policy config
cat config/ttl-policies.yaml
```

**Resolution:**
```bash
# Manually assign TTL
python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
  --job-type test

# Or restart runner to trigger auto-assignment
systemctl restart runner-jobs
```

### Graceful Drain Times Out

**Symptoms:** Drain operation continues beyond timeout; processes not terminating

**Diagnosis:**
```bash
# Check running processes
ps aux | grep -E "runner|job"

# Check for zombie processes
ps aux | grep defunct

# Check system load
top -b -n 1 | head -20
```

**Resolution:**
```bash
# Option 1: Increase timeout and retry
python3 scripts/ephemeral-lifecycle-controller.py drain \
  --strategy graceful \
  --timeout 600  # 10 minutes instead of 5

# Option 2: Force immediate termination
python3 scripts/ephemeral-lifecycle-controller.py drain \
  --strategy forceful
```

### Safe Reap Blocked

**Symptoms:** `check-reap` returns False; runner not being reaped

**Diagnosis:**
```bash
python3 scripts/ephemeral-lifecycle-controller.py check-reap
# Output shows which checks failed

# Check for orphaned processes
ps aux | grep runner
lsof -p <runner_pid>
```

**Resolution:**
```bash
# Option 1: Wait for jobs to complete
sleep 60 && python3 scripts/ephemeral-lifecycle-controller.py check-reap

# Option 2: Force reap (use cautiously)
python3 scripts/ephemeral-lifecycle-controller.py reap --force

# Option 3: Manual cleanup then reap
kill -9 <orphaned_pid>
python3 scripts/ephemeral-lifecycle-controller.py reap
```

### TTL Calculated Incorrectly

**Symptoms:** Unexpected TTL value; doesn't match policy

**Diagnosis:**
```bash
# Check info
python3 scripts/ephemeral-lifecycle-controller.py info

# Verify policy matches job
grep "job_type: build" config/ttl-policies.yaml -A 10

# Check telemetry in state
cat /tmp/runner-ttl-state.json | jq .
```

**Resolution:**
```bash
# Review and update policy
nano config/ttl-policies.yaml

# Verify calculation locally
python3 -c "
from scripts.ephemeral_lifecycle_controller import *
c = EphemeralLifecycleController()
policy = {'ttl_config': {'base_ttl': 1800, 'max_ttl': 3600, 'complexity_multiplier': 1.5}}
print(f'TTL: {c._calculate_ttl(policy)}')
"
```

---

## Examples

### Example 1: Quick Test Job (5 min)

```yaml
name: Unit Tests
on: pull_request

jobs:
  test:
    runs-on: self-hosted-ephemeral
    steps:
      - uses: actions/checkout@v4
      
      - name: Assign TTL for quick test
        run: |
          python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
            --job-type test \
            --duration 300
      
      - name: Run tests
        run: npm test
      
      # Runner automatically reaped after test completes (TTL ~10min)
```

### Example 2: Build Job with Metrics (1 hour)

```yaml
name: Build & Deploy
on: push

jobs:
  build:
    runs-on: self-hosted-ephemeral
    steps:
      - uses: actions/checkout@v4
      
      - name: Get resource metrics (optional)
        id: metrics
        run: |
          CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | awk '{print $1/100}')
          MEM=$(free | grep Mem | awk '{print $3/$2}')
          echo "cpu=$CPU" >> $GITHUB_OUTPUT
          echo "mem=$MEM" >> $GITHUB_OUTPUT
      
      - name: Assign TTL with telemetry
        run: |
          python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
            --job-type build \
            --labels production \
            --cpu-util ${{ steps.metrics.outputs.cpu }} \
            --mem-util ${{ steps.metrics.outputs.mem }}
      
      - name: Build application
        run: cargo build --release
        
      # Runner reaped after build completes
```

### Example 3: Infrastructure Job (4 hours)

```yaml
name: Deploy Infrastructure
on: workflow_dispatch

jobs:
  deploy:
    runs-on: self-hosted-ephemeral-large
    timeout-minutes: 240
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Assign long TTL
        run: |
          python3 scripts/ephemeral-lifecycle-controller.py assign-ttl \
            --job-type infrastructure \
            --labels terraform,production \
            --duration 14400
      
      - name: terraform init
        run: terraform init
      
      - name: terraform apply
        run: terraform apply -auto-approve
      
      # Runner reaped after infrastructure deployment
```

---

## FAQ

### Q: What happens if a runner is reaped while a job is running?

**A:** Safe reap checks for running processes before terminating. If a job is running, reap is blocked. The runner won't be forcefully terminated while processing a job.

### Q: Can I extend TTL if my job needs more time?

**A:** Yes, up to `max_extensions` limit (default: 3). Each extension multiplies TTL by `extension_multiplier` (default: 1.2x). Extension requests require admin API call or explicit workflow action.

### Q: What's the difference between graceful and forceful drain?

**A:** 
- **Graceful:** Waits for jobs to finish (up to timeout), then cleanly shuts down
- **Forceful:** Immediately terminates all processes after grace period

Use graceful for normal shutdowns, forceful for emergency terminations.

### Q: How do audit logs help with compliance?

**A:** Audit logs are append-only and immutable, providing a complete record of:
- When runners were created and assigned TTL
- When jobs started and ended
- When TTL was extended
- When and how runners were terminated

This enables compliance audits, debugging, and cost analysis.

### Q: Can I use custom TTL policies?

**A:** Yes! Edit `config/ttl-policies.yaml` to add or modify policies. Each policy can have custom base TTL, max TTL, and filters for matching jobs.

### Q: What happens if a process ignores termination signals?

**A:** Graceful drain sends SIGTERM first (5-minute wait), then SIGKILL if needed. Forceful drain skips the waiting period and kills immediately.

### Q: How do multiple-runner fleets handle TTL consistency?

**A:** All runners load the same `config/ttl-policies.yaml` from the repo. Policies are version-controlled and can be updated with no downtime (runners pick up new policies on restart).

### Q: Can AI-Oracle help optimize TTL?

**A:** Yes (optional, future feature). AI-Oracle can analyze job patterns and recommend optimal TTL values. Integration is disabled by default; set `ai_oracle.enabled: true` in config to activate.

---

## Contact & Support

For issues, questions, or feature requests:

- **GitHub Issues:** [Issue Tracker](https://github.com/kushin77/self-hosted-runner/issues)
- **Documentation:** [Main README](../self_healing/README.md)
- **Slack:** #infrastructure-support

---

**Last Updated:** 2026-03-09  
**Version:** 1.0  
**Status:** Production Active
