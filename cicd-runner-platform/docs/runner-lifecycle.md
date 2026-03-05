# Runner Lifecycle Guide

## Overview

This document describes the complete lifecycle of a self-hosted GitHub Actions runner from boot to destruction, with emphasis on self-healing and autonomous operations.

## States

A runner can be in one of the following states:

- **Booting**: Initial CloudInit execution, dependency installation
- **Registering**: Runner registration with GitHub
- **Idle**: Waiting for jobs
- **Running**: Executing a job
- **Updating**: Downloading and applying updates
- **Healing**: Self-diagnosing and recovering from failure
- **Quarantined**: Unhealthy, awaiting manual intervention or destruction
- **Destroying**: Graceful shutdown and cleanup

## State Transitions

```
Booting
   ↓
Registering → Idle ↔ Running
              ↑ ↓
            Updating
              ↑ ↓
           Healing
              ↓
         Quarantined
              ↓
           Destroying
```

## Detailed Phases

### 1. Boot Phase (Booting)

**Duration**: ~2-5 minutes

**Steps**:
1. CloudInit execution triggered
2. Bash/PowerShell script (`bootstrap.sh` or `bootstrap.ps1`) starts
3. Host verification (CPU, RAM, disk, security baseline)
4. Dependency installation (git, docker, cosign, syft, etc.)
5. Runner user creation
6. Runner binary download and installation
7. Systemd service registration
8. First health check

**Success**: Runner service active, ready for registration
**Failure**: Job fails; manual intervention or auto-destroy on retry

### 2. Registration Phase (Registering)

**Duration**: ~30 seconds

**Steps**:
1. GitHub registration token provided (env var or secrets manager)
2. `register-runner.sh` invoked
3. Runner connects to GitHub API
4. Runner authenticates with token
5. Runner metadata stored locally (`.runner`, `.credentials`)
6. Listener configured to poll GitHub

**Success**: Runner listed in GitHub Actions settings
**Failure**: Registration times out or token invalid; quarantine

### 3. Idle Phase (Idle)

**Duration**: Variable, hours to days

**Loop** (every 30-60 seconds):
1. Poll GitHub Actions API for jobs assigned to this runner
2. Check health metrics
3. Report metrics to observability stack
4. If update available and no jobs: trigger update
5. If health check fails: trigger healing

**Metrics exported**:
- Runner status (online/offline)
- Job queue depth
- Last heartbeat
- Resource usage

### 4. Job Execution Phase (Running)

**Duration**: Job-specific, typically seconds to minutes

**Steps**:

1. **Job Pull**
   - GitHub sends job details (steps, environment, artifacts)
   - Runner creates job context

2. **Workspace Setup**
   - Create ephemeral workspace: `/tmp/job-<uuid>`
   - Mount job code from GitHub repo (read-only)
   - Set environment variables (secrets injected from API)
   - Create isolated Docker network

3. **Sandbox Initialization**
   - Spin up container with sandboxing (docker, gvisor, firecracker)
   - Mount workspace into container
   - Set resource limits (CPU, memory, disk I/O)
   - Disable network egress (except to approved hosts)

4. **Step Execution**
   - For each step in the job:
     - Log step details
     - Execute step command in sandbox
     - Capture stdout/stderr
     - Tag logs with step name and index
     - If step fails: continue or fail job (depends on `continue-on-error`)

5. **Artifact Collection**
   - Collect build artifacts from workspace
   - Generate SBOM (Syft)
   - Scan for vulnerabilities (Trivy)
   - Sign artifacts (Cosign)
   - Upload artifacts to GitHub Releases or registry

6. **Workspace Cleanup** ⚠️ **CRITICAL**
   - Unmount workspace from container
   - Destroy container
   - Securely wipe workspace directory (shred sensitive files)
   - Clear environment variables
   - Clear shell history
   - Destroy isolated Docker network
   - Remove temp directories

7. **Telemetry**
   - Upload job result to GitHub
   - Send metrics to Prometheus: job duration, status, artifact hashes
   - Send logs to Loki: full job execution log
   - Send traces to Tempo: job span with nested step spans

**Key**: After job, workspace is destroyed. Workspace is never reused across jobs.

### 5. Update Phase (Updating)

**Triggered**: 
- Periodically (every `UPDATE_INTERVAL`, default 1 hour)
- On health check degradation
- On manual override

**Duration**: ~5-15 minutes

**Steps**:

1. **Pre-update Checks**
   - Verify no jobs running (wait up to 30 min)
   - Backup current runner binary and config

2. **Download**
   - Fetch latest runner release from GitHub Actions runner repo
   - Verify signature (if available)
   - Check SHA256 hash

3. **Update**
   - Stop runner service
   - Extract new runner binary
   - Preserve `.runner` and `.credentials` files
   - Execute any migration scripts

4. **Post-update Validation**
   - Verify runner binary health
   - Start runner service
   - Wait 30 seconds for stabilization
   - Run health check

5. **Rollback** (if validation fails)
   - Restore from backup
   - Log rollback event
   - Alert ops team
   - Mark runner as degraded

**Metrics**:
- Update attempts
- Update success rate
- Rollback count
- Time-to-update

### 6. Self-Healing Phase (Healing)

**Triggered**: Health check score > 2/6

Checks:
- Runner process status
- Network connectivity
- Disk space > 80% full
- Memory usage > 90%
- Docker daemon (if applicable)
- Zombie processes > 10

**Duration**: ~1-5 minutes

**Steps**:

1. **Diagnostics**
   - Collect system logs
   - Export current process list
   - Check recent job failures
   - Analyze recent metrics

2. **Attempted Recovery**
   - Stop runner service (graceful)
   - Kill any stuck processes
   - Clean disk (remove old containers, job artifacts)
   - Restart Docker daemon
   - Restart runner service

3. **Validation**
   - Wait 10 seconds for stability
   - Re-run health checks
   - If score now ≤ 2: declare success
   - If score still > 2: escalate to quarantine

4. **Quarantine** (if recovery failed)
   - Set `.quarantined` flag
   - Stop accepting new jobs
   - Log quarantine event with diagnostics
   - Signal ops team (email, Slack, PagerDuty)
   - Wait for manual intervention or auto-destroy signal

## Detailed Destruction Walkthrough

**Triggered by**:
- Manual: `destroy-runner.sh` called
- Automatic: After N healing failures or explicit signal
- Cloud: Scale-down event (Kubernetes, EC2, GCP)

**Duration**: ~1-2 minutes

**Steps** (in order):

1. **Drain** (if jobs running)
   - Signal runner to stop accepting jobs
   - Wait for running jobs to complete (timeout 30 min)
   - Force-kill jobs after timeout

2. **Unregister**
   - Call GitHub API to unregister runner
   - Delete from GitHub Actions settings
   - Remove runner from runners list

3. **Stop Service**
   - Stop systemd service
   - Disable autostart
   - Remove service file

4. **Credential Wipe** ⚠️ **CRITICAL**
   - Use `shred` (10-pass overwrite) on:
     - `.runner` file
     - `.credentials` file
     - `.credentials_rsaparams` file
     - Any env var files
   - Zero out memory (best effort)

5. **Artifact Cleanup**
   - Remove all job workspaces
   - Remove Docker containers/images
   - Clear temp directories
   - Clear shell history

6. **System Cleanup**
   - Remove runner user from system
   - Remove observability agents
   - Remove scheduled tasks / cron jobs
   - Remove log files (with retention for audit)

7. **Audit Log**
   - Write destruction event to immutable audit log
   - Include timestamp, hostname, reason, GitHub URL
   - Sign audit entry if possible

8. **Final Steps**
   - Optional: halt the machine (`shutdown -h +1`)
   - Optional: signal orchestrator to decommission VM/K8s pod
   - Optional: send destruction notification

## Monitoring & Observability

### Key Metrics

- `runner_status` (gauge): 0 = offline, 1 = idle, 2 = running
- `runner_job_duration_seconds` (histogram): Job execution time
- `runner_job_result` (counter): Pass/fail jobs
- `runner_health_score` (gauge): 0-6 (0 = healthy)
- `runner_updates_total` (counter): Update attempts
- `runner_updates_rollback_total` (counter): Rollback count
- `runner_quarantine_total` (counter): Quarantine events

### Dashboards

- **Runner Health**: Status, health score, uptime
- **Job Trends**: Throughput, duration, failure rate by type
- **Resource Usage**: CPU, memory, disk per runner
- **Security**: Artifact scans, policy violations, secret detections

### Alerts

- Runner offline > 5 min
- Job failure rate > 10%
- Disk usage > 90%
- Healing failure → quarantine
- Update failure → rollback

## Examples

### Deploy a runner on EC2 with Auto-Healing

```bash
#!/usr/bin/env bash
# cloud-init user-data

git clone https://github.com/YOUR_ORG/self-hosted-runner /opt/runner-platform
cd /opt/runner-platform/bootstrap

export RUNNER_TOKEN=${RUNNER_TOKEN}
export RUNNER_URL=https://github.com
export RUNNER_LABELS=aws,ec2

./bootstrap.sh

# Enable auto-healing daemon
cat > /etc/systemd/system/runner-health-daemon.service <<EOF
[Unit]
Description=Runner Health Check Daemon
After=actions-runner.service

[Service]
Type=simple
ExecStart=/opt/runner-platform/scripts/health-check.sh --daemon 300
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable runner-health-daemon.service
systemctl start runner-health-daemon.service
```

### Monitor Runner Health in Prometheus

```prometheus
# Scrape every 30 seconds
runner:health:score = avg(runner_health_score)

# Alert on degradation
alert: RunnerUnhealthy
  if: runner:health:score < 2 for 10m
  annotations:
    summary: "Runner {{ $labels.instance }} is unhealthy"
```

### Manual Quarantine & Destruction

```bash
# Mark runner as unhealthy
touch /opt/runner-platform/.quarantined

# Wait for graceful drain (max 30 min)
sleep 1800

# Destroy
GITHUB_TOKEN=${GITHUB_TOKEN} /opt/runner-platform/scripts/destroy-runner.sh
```

## Appendix: File Locations

| File | Purpose |
|------|---------|
| `/opt/actions-runner/` | Runner installation |
| `/var/log/runner-*` | Runner logs |
| `/var/log/runner-audit.log` | Audit trail (immutable append) |
| `/etc/systemd/system/actions-runner.service` | Systemd unit |
| `~/.runner` | Runner registration metadata |
| `~/.credentials` | GitHub registration token (SENSITIVE) |

## Safety Guarantees

1. **Workspace isolation**: No file leakage between jobs
2. **Secret isolation**: Secrets never logged or persisted
3. **Cleanup guarantee**: Ephemeral workspaces always cleaned
4. **Audit trail**: All actions logged immutably
5. **Self-healing**: Automatic recovery without manual intervention
6. **Graceful degradation**: Quarantine before data loss

