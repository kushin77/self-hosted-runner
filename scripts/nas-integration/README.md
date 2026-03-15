# 🗄️ NAS Integration for On-Premises Infrastructure

**Complete Solution for Centralized Configuration Management with NAS**

## Overview

This enhancement enables your on-premises infrastructure to use a centralized NAS server (192.168.168.100) as the canonical source for:
- **Infrastructure-as-Code (IAC)** - Terraform, Kubernetes manifests, Docker configs
- **Configuration Vault** - Encrypted application configurations
- **Service Credentials** - SSH keys, API tokens from GCP Secret Manager
- **Audit Trails** - Immutable records of all sync operations

### Benefits

✅ **Single Source of Truth** - NAS is canonical, eliminates drift  
✅ **Automated Syncing** - 30-minute intervals keep worker nodes current  
✅ **Ephemeral Worker Nodes** - Can restart/reboot anytime without data loss  
✅ **Dev Node Push** - Developers can update configs locally, auto-propagate  
✅ **Zero Manual Intervention** - Fully automated via systemd timers  
✅ **Audit & Compliance** - All operations logged with timestamps  
✅ **Health Monitoring** - Automated health checks every 15 minutes  
✅ **Production Grade** - Enterprise security with Ed25519 SSH keys  

---

## Quick Start

### For Impatient People (2 minutes)

```bash
# 1. Clone this repo
cd /path/to/self-hosted-runner

# 2. Deploy to worker & dev nodes
bash deploy-nas-integration.sh all

# 3. Verify
ssh automation@192.168.168.42 'sudo systemctl status nas-worker-sync.timer'
# Should show: Active: active (waiting)

✅ Done! Sync runs every 30 minutes automatically.
```

### For Careful People (10 minutes)

Follow the **[5-Minute Quick Start](docs/NAS_QUICKSTART.md)** guide which covers:
- Step-by-step setup for worker node
- Step-by-step setup for dev node
- Verification commands
- Troubleshooting 1-liners

### For Thorough People (1 hour)

Read the **[Complete Integration Guide](docs/NAS_INTEGRATION_COMPLETE.md)** with:
- Architecture deep-dive
- Detailed prerequisites
- Production setup procedures
- Advanced configuration
- Security considerations
- Troubleshooting guide
- Operations procedures

---

## Architecture

### Data Flow

```
┌─────────────────┐     Rsync SSH      ┌──────────────────┐     Rsync    ┌──────────────────┐
│  Dev Node       │     (30min)        │  NAS Repository  │    (30min)   │  Worker Node     │
│  .31            │ ────────────────► │  .100            │ ──────────► │  .42             │
├─────────────────┤                     ├──────────────────┤             ├──────────────────┤
│ /opt/iac-configs│ (manual push)      │ /repositories/   │ (pull)      │ /opt/nas-sync/   │
│ Git repository  │   or watch mode    │ /config-vault/   │             │   ├─ iac/        │
│ Developers      │                     │ GSM access       │             │   ├─ configs/    │
└─────────────────┘                     └────────┬─────────┘             │   └─ audit/      │
                                                 │                       └──────────────────┘
                                                 ▼
                                        GCP Secret Manager
                                      (credentials & keys)
```

### Key Files

| Location | Purpose | Runs On |
|----------|---------|---------|
| `scripts/nas-integration/worker-node-nas-sync.sh` | Pull from NAS | Worker node (every 30 min) |
| `scripts/nas-integration/dev-node-nas-push.sh` | Push to NAS | Dev node (manual or watch) |
| `scripts/nas-integration/healthcheck-worker-nas.sh` | Health validation | Worker node (every 15 min) |
| `systemd/nas-*.service` | Systemd units | Both nodes (auto-start) |
| `systemd/nas-*.timer` | Systemd timers | Both nodes (scheduling) |
| `docker/prometheus/nas-integration-rules.yml` | Monitoring alerts | Prometheus |
| `docs/NAS_INTEGRATION_COMPLETE.md` | Full documentation | Reference |

---

## Installation

### Automated (Recommended)

```bash
# One command deploys to both nodes
bash deploy-nas-integration.sh all

# Or specific node
bash deploy-nas-integration.sh worker   # Worker node only
bash deploy-nas-integration.sh dev      # Dev node only
```

### Manual (See docs)

Follow section **[Worker Node Setup](docs/NAS_INTEGRATION_COMPLETE.md#worker-node-setup)** in the complete guide.

---

## Operations

### Start Syncing

```bash
# Worker node automatically syncs every 30 minutes (systemd timer)
# Check status:
sudo systemctl status nas-worker-sync.timer

# Force immediate sync:
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# Or via systemd:
sudo systemctl start nas-worker-sync.service
```

### Push Changes (Dev Node)

```bash
# One-time push
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push

# See pending changes
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff

# Continuous watch (auto-push on changes)
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch
```

### Monitor Health

```bash
# Detailed health report
bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh --verbose

# View sync audit trail
tail -20 /opt/nas-sync/audit/sync-audit-trail.jsonl | jq '.'

# Last successful sync time
cat /opt/nas-sync/audit/.last-success | date -f - "+Last sync: %Y-%m-%d %H:%M:%S"
```

---

## Troubleshooting

### "Cannot connect to NAS"

```bash
# Test SSH access
ssh -i ~/.ssh/id_ed25519 elevatediq-svc-nas@192.168.168.100 echo "OK"

# Check authorized_keys on NAS
# Verify your public key is present
```

### "Sync stale" warning

```bash
# Force manual sync
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# Check systemd timer
sudo systemctl status nas-worker-sync.timer
sudo journalctl -u nas-worker-sync.service -n 50
```

### "Disk usage high"

```bash
# Check sync directory size
du -sh /opt/nas-sync

# Clean old audit logs
find /opt/nas-sync/audit -name "*.log" -mtime +7 -delete

# See full troubleshooting: docs/NAS_INTEGRATION_COMPLETE.md#troubleshooting
```

---

## Monitoring & Alerts

Prometheus alerts automatically fire for:
- ❌ NAS server unreachable
- ❌ Sync stale (>1 hour without update)
- ❌ Failed credential fetch
- ❌ Permission errors on credentials
- ⚠️ High disk usage
- ⚠️ Integrity issues

Configure in: `docker/prometheus/nas-integration-rules.yml`

---

## Security

### SSH Keys
- Ed25519 encryption (modern, strong)
- Stored in `/home/automation/.ssh/id_ed25519`
- 600 permissions (user read/write only)
- Never in Git or logs

### Credentials
- Fetched from GCP Secret Manager (via NAS SSH)
- Never stored on disk permanently
- Temporary files shredded after use
- Audit trail for all access

### Audit Trail
- JSON Lines format (append-only)
- Timestamps and session IDs
- Success/failure status
- Cannot be modified retroactively

---

## Files & Directories

```
self-hosted-runner/
├── scripts/nas-integration/           ← Main scripts
│   ├── worker-node-nas-sync.sh        (~300 lines)
│   ├── dev-node-nas-push.sh           (~300 lines)
│   └── healthcheck-worker-nas.sh      (~200 lines)
│
├── systemd/                           ← Systemd services
│   ├── nas-worker-sync.service
│   ├── nas-worker-sync.timer
│   ├── nas-worker-healthcheck.service
│   ├── nas-worker-healthcheck.timer
│   ├── nas-dev-push.service
│   └── nas-integration.target
│
├── docs/                              ← Documentation
│   ├── NAS_INTEGRATION_COMPLETE.md    (5000+ lines)
│   ├── NAS_QUICKSTART.md              (150 lines)
│   └── NAS_INTEGRATION_GUIDE.md       (existing)
│
├── docker/prometheus/
│   └── nas-integration-rules.yml      (Monitoring alerts)
│
└── deploy-nas-integration.sh          (One-stop deployment)
```

---

## Support

### Documentation

| Document | Purpose | Length |
|----------|---------|--------|
| [NAS_QUICKSTART.md](docs/NAS_QUICKSTART.md) | 5-minute setup | 150 lines |
| [NAS_INTEGRATION_COMPLETE.md](docs/NAS_INTEGRATION_COMPLETE.md) | Everything | 5000+ lines |
| [NAS_INTEGRATION_GUIDE.md](docs/NAS_INTEGRATION_GUIDE.md) | eiq-nas details | 600 lines |

### Common Tasks

- **First time setup**: Follow [NAS_QUICKSTART.md](docs/NAS_QUICKSTART.md)
- **Deep understanding**: Read [NAS_INTEGRATION_COMPLETE.md](docs/NAS_INTEGRATION_COMPLETE.md)
- **Troubleshooting**: See NAS_INTEGRATION_COMPLETE.md → Troubleshooting section
- **Monitoring**: Configure Prometheus using nas-integration-rules.yml
- **Advanced config**: See NAS_INTEGRATION_COMPLETE.md → Operations section

### Quick Commands

```bash
# Deploy
bash deploy-nas-integration.sh all

# Test worker sync
bash /opt/automation/scripts/nas-integration/worker-node-nas-sync.sh

# Test dev push
bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push

# Check health
bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh --verbose

# Monitor in real-time
journalctl -u nas-worker-sync.service -f
journalctl -u nas-dev-push.service -f
```

---

## Status

🟢 **Production Ready**
- ✅ All scripts tested and commented
- ✅ Comprehensive documentation
- ✅ Systemd integration complete
- ✅ Monitoring & alerting configured
- ✅ Security hardened (SSH keys, credentials from GSM)
- ✅ Audit trail implemented

---

## Next Steps

1. **Review**: Read [docs/NAS_QUICKSTART.md](docs/NAS_QUICKSTART.md)
2. **Test**: Deploy to staging first
3. **Monitor**: Watch health checks for 24 hours
4. **Deploy**: Follow [docs/NAS_INTEGRATION_COMPLETE.md](docs/NAS_INTEGRATION_COMPLETE.md)
5. **Operate**: Use Quick Commands above for daily tasks

---

**Version**: 1.0  
**Date**: March 14, 2026  
**Status**: 🟢 Production Ready  
**Owner**: Infrastructure Team
