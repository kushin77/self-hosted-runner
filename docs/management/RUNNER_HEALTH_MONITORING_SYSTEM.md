# Runner Health Monitoring System

## Overview

The health monitoring system continuously tracks the state of all self-hosted GitHub Actions runners, ensuring availability, performance, and quick incident response.

## Architecture

### Health Check Components

1. **Periodic Health Monit (5-minute intervals)**
   - Checks runner process status
   - Verifies GitHub API connectivity
   - Validates disk space and resource utilization
   - Reports metrics to Prometheus

2. **Exponential Backoff Recovery**
   - Initial retry: 10 seconds
   - Step 2: 40 seconds  
   - Step 3+: 80 seconds
   - Max age before force restart: 60 minutes

3. **Cleanup Tasks**
   - Stale process detection
   - Workspace permissions normalization
   - Pytest hygiene (kill stuck processes)
   - Disk space management

## Monitoring Endpoints

| Endpoint | Type | Interval |
|----------|------|----------|
| `/health` | Liveness | 30s |
| `/ready` | Readiness | 60s |
| `/metrics` | Prometheus | 15s |

### Key Metrics

- `runner_health_status` (0/1 - unhealthy/healthy)
- `runner_uptime_seconds` (total uptime)
- `runner_job_count` (jobs executed)
- `runner_disk_usage_percent` (storage utilization)
- `runner_memory_usage_percent` (RAM usage)

## Alerting

### Critical Alerts

| Alert | Threshold | Action |
|-------|-----------|--------|
| Runner Down | 5 min without heartbeat | Page DevOps |
| Disk Full | >90% | Force cleanup, expand volume |
| Memory Leak | >95% sustained | Restart runner |
| Job Stuck | >60 min | Kill + restart |

## Configuration

Environment variables for health monitoring:

```bash
HEALTH_CHECK_INTERVAL=300        # 5 minutes
HEALTH_CHECK_TIMEOUT=30          # 30 seconds
RECOVERY_BACKOFF_INITIAL=10      # 10 seconds
RECOVERY_BACKOFF_MAX=80          # 80 seconds
RECOVERY_MAX_AGE=3600            # 60 minutes
```

## Operations

### Manual Health Check

```bash
./runner_health_monitor.sh --check
./runner_health_monitor.sh --repair
./runner_health_monitor.sh --status
```

### Systemd Integration

```bash
systemctl status elevatediq-runner-health-monitor.service
systemctl status elevatediq-runner-health-monitor.timer
```

### Incident Response

1. Alert triggered (runner down)
2. Auto-recovery attempt (3 retries with backoff)
3. Manual intervention if auto-recovery fails
4. Post-incident review and root cause analysis

## See Also

- [Runner Infrastructure](RUNNER_INFRASTRUCTURE_DEPLOYMENT.md)
- [Governance Policies](../governance/runners.md)
