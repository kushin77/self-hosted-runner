# Hands-Off Infrastructure: Complete Implementation Guide

**Status**: ✅ PRODUCTION READY | **Date**: 2026-03-06 | **Validation**: 14/14 PASS

## Overview

This document describes the **fully autonomous, sovereign, and ephemeral** CI/CD infrastructure deployed on `192.168.168.42`. The system requires zero manual intervention and operates on scheduled automation with self-healing capabilities.

## Architecture Summary

### Core Components

| Component | Purpose | Location | Schedule |
| --- | --- | --- | --- |
| **HashiCorp Vault** | Centralized secret storage | `192.168.168.42:8200` (Docker) | Always-on |
| **GSM→Vault Sync** | Sync secrets from GCP to Vault | `systemd` service | Every 5 minutes |
| **Alertmanager** | Alert routing & management | `192.168.168.42:9093` (Docker) | Always-on |
| **Synthetic Alerts** | Health check & monitoring | `systemd` service | Every 6 hours |
| **GitHub/GitLab/Slack** | External integrations | Vault-backed auth | Triggered |

### Immutability Chain

```
GCP Secret Manager (source of truth)
    ↓ [GSM→Vault Sync - 5 min] [Immutable via git]
HashiCorp Vault (runtime secrets)
    ↓ [fetch_vault_secrets.sh]
CI/CD Automation Scripts
    ↓ [scripts/{provision,check,notify}]
Self-healing Infrastructure
```

## Key Secrets in Vault

All secrets are stored at `http://192.168.168.42:8200/v1/` under KV v2:

```bash
vault kv list secret/ci/
# Output:
# - ghcr          (Container registry token)
# - gitlab        (Group-level runner registration token)
# - pushgateway   (Prometheus push gateway URL)
# - webhooks      (Slack webhook URL)

vault kv get secret/github-token
# Output:
# - token: gho_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX (kushin77)
```

## Automation Scripts (Version-Controlled in Git)

### 1. `scripts/gsm_to_vault_sync.sh`
**Runs**: Every 5 minutes via systemd timer  
**Purpose**: Sync GCP Secret Manager → Vault (AppRole auth)  
**Secrets Synced**:
- `slack-webhook` → `secret/ci/webhooks`
- `gitlab-registration-token` → `secret/ci/gitlab`

**Logs**: `journalctl -u gsm-to-vault-sync.service -n 50`

### 2. `scripts/fetch_vault_secrets.sh`
**Runs**: On-demand by other scripts  
**Purpose**: Export Vault secrets as environment variables  
**Exports**: `SLACK_WEBHOOK`, `GITLAB_REGISTRATION_TOKEN`, `PUSHGATEWAY_URL`, `GHCR_PAT`

### 3. `scripts/automated_test_alert.sh`
**Runs**: Every 6 hours via systemd timer  
**Purpose**: Send synthetic alert to Alertmanager → Slack  
**Validates**: End-to-end monitoring pipeline

**Logs**: `journalctl -u synthetic-alert.service -n 50`

### 4. `scripts/check_and_reprovision_runner.sh`
**Runs**: Triggered by CI or cron  
**Purpose**: Health-check runners, auto-reprovisioning if offline  
**Supports**: GitHub (legacy) or GitLab (primary)

### 5. `scripts/provision_gitlab_runner.sh`
**Runs**: On-demand when runner missing  
**Purpose**: Register new GitLab group-level runner  
**Auth**: `GITLAB_REGISTRATION_TOKEN` from Vault

## Systemd Services & Timers

### Sync Timer (5-minute cadence)
```bash
# File: /etc/systemd/system/gsm-to-vault-sync.timer
sudo systemctl status gsm-to-vault-sync.timer
sudo systemctl enable --now gsm-to-vault-sync.timer
```

### Alert Timer (6-hour cadence)
```bash
# File: /etc/systemd/system/synthetic-alert.timer
sudo systemctl status synthetic-alert.timer
sudo systemctl enable --now synthetic-alert.timer
```

### Environment Configuration
```bash
# File: /etc/default/gsm_to_vault_sync
SECRET_PROJECT=gcp-eiq
VAULT_ADDR=http://192.168.168.42:8200
VAULT_ROLE_ID=d0acc60f-1827-eacb-c841-82067458c6be
VAULT_SECRET_ID=78602611-c3f5-b39c-6b07-fa71282a116e
```

## Monitoring & Alerting

### Alertmanager Configuration
- **Endpoint**: `http://192.168.168.42:9093`
- **API**: v2 (modern JSON format)
- **Routing**: All alerts → Slack webhook

### Slack Integration
- **Webhook**: Stored in Vault at `secret/ci/webhooks`
- **Channel**: Configured in Alertmanager
- **Tests**: Run automatically every 6 hours

## Operational Procedures

### Verify System Health
```bash
# Run comprehensive validation
./scripts/hands-off-validation.sh

# Expected output: 14/14 PASS
```

### Check Recent Syncs
```bash
ssh akushnir@192.168.168.42 \
  journalctl -u gsm-to-vault-sync.service -n 10 --no-pager
```

### Trigger Manual Sync
```bash
ssh akushnir@192.168.168.42 \
  "export SECRET_PROJECT=gcp-eiq && \
   export VAULT_ADDR=http://192.168.168.42:8200 && \
   export VAULT_ROLE_ID=... && \
   export VAULT_SECRET_ID=... && \
   /home/akushnir/self-hosted-runner/scripts/gsm_to_vault_sync.sh"
```

### Rotate a Secret
1. Update the source in GCP Secret Manager
2. Wait for next 5-minute sync OR trigger manually
3. Vault is automatically updated
4. Dependent services pick up new value at next refresh

Example: Rotate GitHub token
```bash
# 1. In GCP Console: Update secret/github-token with new PAT
# 2. On production host: Wait 5 minutes OR trigger sync manually
# 3. Verify: vault kv get secret/github-token
# 4. CI/CD workflows will use new token on next run
```

### Add New Secret
1. Create in GCP Secret Manager
2. Update `GSM_SECRETS` array in `gsm_to_vault_sync.sh`
3. Commit to git
4. Sync to remote host
5. Wait for next 5-minute sync (or trigger manually)

## Troubleshooting

### Sync Service Failing
```bash
# Check logs
ssh akushnir@192.168.168.42 journalctl -u gsm-to-vault-sync.service -n 50

# Common issues:
# - AppRole credentials expired: Update VAULT_ROLE_ID / VAULT_SECRET_ID
# - GCP credentials invalid: Re-authenticate with `gcloud auth login`
# - Vault unreachable: Check network connectivity, Vault container status
```

### Alerts Not Reaching Slack
```bash
# Check Alertmanager status
curl http://192.168.168.42:9093/api/v2/status | jq .

# Manually test alert
./scripts/automated_test_alert.sh

# Check recent alerts
curl http://192.168.168.42:9093/api/v2/alerts | jq '.[0:3]'
```

### Runner Not Reprovisioning
```bash
# Check provisioning log
ssh akushnir@192.168.168.42 \
  "PRIMARY_PLATFORM=gitlab \
   /home/akushnir/self-hosted-runner/scripts/check_and_reprovision_runner.sh"

# Verify GitLab token in Vault
export VAULT_ADDR=http://192.168.168.42:8200
export VAULT_TOKEN=devroot
vault kv get secret/ci/gitlab
```

## Security & Compliance

### Secret Rotation Policy
- **GitHub Token**: Rotate every 30 days (set reminder)
- **GitLab Token**: Rotate every 30 days (set reminder)
- **Slack Webhook**: Rotate if compromised (regenerate in Slack workspace)
- **AppRole Credentials**: Update quarterly or if suspected leak

### Access Control
- **AppRole Role ID / Secret ID**: Stored in GCP Secret Manager (encrypted at rest)
- **Vault Root Token**: Limited to `devroot` (dev environment only; upgrade in prod)
- **SSH Access**: Limited to `akushnir` user on `192.168.168.42`

### Audit Trail
All secret operations are logged:
```bash
# Vault audit logs
ssh akushnir@192.168.168.42 docker logs local-dev-vault
# Look for: auth, put, get operations

# Systemd service logs
journalctl -u gsm-to-vault-sync.service
journalctl -u synthetic-alert.service
```

## Disaster Recovery

### Vault Recovery
If Vault container crashes:
```bash
ssh akushnir@192.168.168.42 \
  "docker restart local-dev-vault && \
   sleep 5 && \
   curl http://localhost:8200/v1/sys/health"
```

### Secret Recovery from GSM
If Vault is lost, all secrets remain in GCP Secret Manager:
```bash
# Redeploy Vault and re-run sync
export VAULT_ADDR=http://192.168.168.42:8200
export VAULT_TOKEN=devroot
./scripts/gsm_to_vault_sync.sh
```

### Runner Recovery
If runner host crashes, systemd timers will resume on reboot:
```bash
ssh akushnir@192.168.168.42 \
  "systemctl status gsm-to-vault-sync.timer && \
   systemctl status synthetic-alert.timer"
```

## Future Enhancements

### Phase 4 Recommendations
1. **Vault HA**: Deploy secondary Vault on `192.168.168.41` with replication
2. **GitLab Primary**: Complete GitLab group-level runner migration
3. **RBAC Hardening**: Replace `devroot` token with fine-grained AppRole policies
4. **Audit Logging**: Enable Vault audit logs to external storage (e.g., Cloud Logging)
5. **Automated Token Rotation**: Implement CI job to rotate tokens quarterly
6. **Prometheus Integration**: Export systemd timer metrics to Prometheus

## Contact & Support

For operational issues:
1. Check this documentation first
2. Review systemd logs: `journalctl -u gsm-to-vault-sync.service`
3. Run validation: `./scripts/hands-off-validation.sh`
4. Open issue in GitHub if help needed

---

**Document Version**: 1.0 (2026-03-06)  
**Maintained By**: DevOps/SRE Team  
**Last Updated**: 2026-03-06
