# Service Account Architecture & Deployment Strategy

**Status:** ✅ **PRODUCTION ARCHITECTURE**  
**Effective:** 2026-03-14  
**Version:** 2.0 - SSH Key-Only Mandate  
**Authority:** Engineering + Security Teams

---

## Executive Summary

All service accounts MUST use SSH key-only authentication via Ed25519 keys stored in GSM/Vault with automatic 90-day rotation. This document defines the complete service account ecosystem, deployment topology, and operational procedures.

---

## Service Account Categories & Purposes

### Category 1: Infrastructure Deployment (7 accounts)

Accounts responsible for deploying, configuring, and managing infrastructure.

| Account | Hosts | Purpose | Access Level | Rotation |
|---------|-------|---------|--------------|----------|
| `nexus-deploy-automation` | .42 | Infrastructure deployment automation | Limited (deploy only) | 90-day |
| `nexus-k8s-operator` | .42 | Kubernetes cluster operations | Limited (k8s-admin) | 90-day |
| `nexus-terraform-runner` | .42 | Terraform plan/apply operations | Limited (infra-modify) | 90-day |
| `nexus-docker-builder` | .31, .42 | Docker image building and registry push | Limited (build only) | 90-day |
| `nexus-registry-manager` | Cloud | Container registry management | Limited (registry-admin) | 90-day |
| `nexus-backup-manager` | .39 (NAS) | Backup and snapshot operations | Limited (backup-only) | 90-day |
| `nexus-disaster-recovery` | .42, .39 | DR operations and failover | Limited (dr-operations) | 90-day |

### Category 2: Application Services (8 accounts)

Service accounts for running applications and microservices.

| Account | Hosts | Purpose | Access Level | Rotation |
|---------|-------|---------|--------------|----------|
| `nexus-api-runner` | .42 | REST API service execution | Limited (app-only) | 90-day |
| `nexus-worker-queue` | .42 | Background job processing | Limited (worker-only) | 90-day |
| `nexus-scheduler-service` | .42 | Cloud Scheduler orchestration | Limited (schedule-only) | 90-day |
| `nexus-webhook-receiver` | .42 | GitHub webhook processing | Limited (webhook-only) | 90-day |
| `nexus-notification-service` | .42 | Alert and notification delivery | Limited (notify-only) | 90-day |
| `nexus-cache-manager` | .42 | Redis and cache operations | Limited (cache-only) | 90-day |
| `nexus-database-migrator` | .42 | Database schema changes | Limited (migration-only) | 90-day |
| `nexus-logging-aggregator` | .42 | Log collection and processing | Limited (logs-only) | 90-day |

### Category 3: Monitoring & Observability (6 accounts)

Accounts for monitoring, alerts, and observability operations.

| Account | Hosts | Purpose | Access Level | Rotation |
|---------|-------|---------|--------------|----------|
| `nexus-prometheus-collector` | .42 | Prometheus metrics collection | Read-only | 90-day |
| `nexus-alertmanager-runner` | .42 | Alert manager operations | Limited (alerts-only) | 90-day |
| `nexus-grafana-datasource` | .42 | Grafana datasource queries | Read-only | 90-day |
| `nexus-log-ingester` | .42 | Log aggregation service | Limited (ingest-only) | 90-day |
| `nexus-trace-collector` | .42 | Distributed tracing | Limited (traces-only) | 90-day |
| `nexus-health-checker` | .42, .39 | Health and uptime checks | Limited (health-only) | 90-day |

### Category 4: Security & Compliance (5 accounts)

Accounts for security operations and compliance requirements.

| Account | Hosts | Purpose | Access Level | Rotation |
|---------|-------|---------|--------------|----------|
| `nexus-secrets-manager` | Cloud | Secrets management operations | Limited (secrets-write) | 90-day |
| `nexus-audit-logger` | .42 | Append-only audit trail operations | Limited (audit-only) | 90-day |
| `nexus-security-scanner` | .42 | Security scanning and vulnerability checks | Read-only | 90-day |
| `nexus-compliance-reporter` | .42 | Compliance report generation | Limited (report-only) | 90-day |
| `nexus-incident-responder` | .42, .39 | Incident response operations | Limited (incident-ops) | 90-day |

### Category 5: Development & Testing (6 accounts)

Accounts for CI/CD, testing, and development operations.

| Account | Hosts | Purpose | Access Level | Rotation |
|---------|-------|---------|--------------|----------|
| `nexus-ci-runner` | .42 | CI/CD pipeline execution | Limited (ci-only) | 90-day |
| `nexus-test-automation` | .42 | Automated testing | Limited (test-only) | 90-day |
| `nexus-load-tester` | .42 | Load and performance testing | Limited (perf-only) | 90-day |
| `nexus-e2e-tester` | .42 | End-to-end test execution | Limited (e2e-only) | 90-day |
| `nexus-integration-tester` | .42 | Integration test execution | Limited (integration-only) | 90-day |
| `nexus-documentation-builder` | .42 | Documentation generation and publishing | Limited (docs-only) | 90-day |

### Legacy Service Accounts (To be migrated)

These are now upgraded to SSH key-only standard:

| Account | Hosts | Migration Status | Target Date |
|---------|-------|-----------------|-------------|
| `elevatediq-svc-worker-dev` | .42 | ✅ Migrated | 2026-03-14 |
| `elevatediq-svc-worker-nas` | .42 | ✅ Migrated | 2026-03-14 |
| `elevatediq-svc-dev-nas` | .39 | ✅ Migrated | 2026-03-14 |

---

## Deployment Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ Development Host (.31)                                           │
│                                                                  │
│  ├─ Git repository source                                       │
│  ├─ SSH key storage (~/.ssh/svc-keys/)                         │
│  ├─ Deployment trigger (git push)                              │
│  └─ Service Accounts:                                           │
│     ├─ elevatediq-svc-worker-dev (→ .42)                     │
│     ├─ elevatediq-svc-dev-nas (→ .39)                        │
│     ├─ nexus-docker-builder (local)                            │
│     └─ nexus-ci-runner (test-only)                            │
└─────────────────────────────────────────────────────────────────┘
                          ↓ SSH (Keys Only)
┌─────────────────────────────────────────────────────────────────┐
│ Production Host (.42) - NexusShield Infrastructure                │
│                                                                  │
│  Kubernetes Cluster                                             │
│  ├─ Pod A: nexus-api-runner                                    │
│  ├─ Pod B: nexus-worker-queue                                  │
│  ├─ Pod C: nexus-scheduler-service                             │
│  ├─ Pod D: nexus-webhook-receiver                              │
│  └─ Pod E: Monitoring Stack                                    │
│     ├─ nexus-prometheus-collector                              │
│     ├─ nexus-alertmanager-runner                               │
│     └─ nexus-grafana-datasource                                │
│                                                                  │
│  Deployment Agents                                              │
│  ├─ nexus-deploy-automation (deployment-only)                 │
│  ├─ nexus-k8s-operator (cluster-ops)                           │
│  ├─ nexus-terraform-runner (infra-changes)                     │
│  ├─ nexus-secrets-manager (secrets access)                     │
│  └─ nexus-audit-logger (append-only logging)                   │
│                                                                  │
│  Observability Stack                                            │
│  ├─ Prometheus                                                  │
│  ├─ Grafana                                                     │
│  ├─ Loki (logs)                                                 │
│  └─ Trace collector                                             │
│                                                                  │
│  Support Services                                               │
│  ├─ PostgreSQL                                                  │
│  ├─ Redis                                                       │
│  └─ Vault (local replica)                                       │
└─────────────────────────────────────────────────────────────────┘
                          ↓ SSH (Keys Only)
┌─────────────────────────────────────────────────────────────────┐
│ NAS Host (.39) - Backup & Storage                               │
│                                                                  │
│  ├─ NFS storage mounts                                          │
│  ├─ Backup storage                                              │
│  ├─ Disaster recovery snapshots                                 │
│  ├─ Archive storage (compliance)                                │
│  └─ Service Accounts:                                           │
│     ├─ elevatediq-svc-worker-nas (.42 → here)                 │
│     ├─ elevatediq-svc-dev-nas (.31 → here)                   │
│     ├─ nexus-backup-manager                                    │
│     ├─ nexus-disaster-recovery                                 │
│     └─ nexus-health-checker                                    │
└─────────────────────────────────────────────────────────────────┘
        ↓ API Calls (Credentials from SSM)
┌─────────────────────────────────────────────────────────────────┐
│ Cloud Secrets Management                                        │
│                                                                  │
│  Google Secret Manager                                          │
│  ├─ All 32 service account SSH keys                            │
│  ├─ API credentials                                             │
│  ├─ Database passwords                                          │
│  └─ Encrypted with: GCP KMS (AES-256)                          │
│                                                                  │
│  HashiCorp Vault (Secondary/DR)                                │
│  ├─ Replicated keys                                             │
│  ├─ SSH certificate authority                                   │
│  ├─ Dynamic credentials                                         │
│  └─ Encryption: Shamir key shares                              │
│                                                                  │
│  AWS Secrets Manager (Tertiary)                                │
│  ├─ Multi-region replication                                    │
│  ├─ Cross-account access                                        │
│  └─ Automatic rotation integration                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Deployment Pipeline

### Step 1: Key Generation (Automated)

```bash
# Generate 32 Ed25519 SSH key pairs
for account in nexus-deploy-automation nexus-k8s-operator \
               nexus-terraform-runner nexus-docker-builder \
               # ... all 32 accounts
do
    bash scripts/ssh_service_accounts/generate_keys.sh "$account"
done

# Output:
# ├─ secrets/ssh/{account}/id_ed25519 (private key, 600 permissions)
# ├─ secrets/ssh/{account}/id_ed25519.pub (public key)
# ├─ Key fingerprint: SHA256:...
# └─ GSM backup: projects/nexusshield-prod/secrets/{account}/versions/1
```

### Step 2: Key Distribution (Automated)

```bash
# Deploy public keys to all target hosts
bash scripts/ssh_service_accounts/automated_deploy_keys_only.sh

# Phase 1: Deploy to .42 (primary production)
#   ├─ Create service account (Linux user)
#   ├─ Setup ~/.ssh directory (700 permissions)
#   ├─ Distribute public key to authorized_keys
#   └─ Verify SSH access (no password prompt)

# Phase 2: Deploy to .39 (NAS)
#   ├─ Create service account (Linux user)
#   ├─ Setup ~/.ssh directory (700 permissions)
#   ├─ Distribute public key to authorized_keys
#   └─ Verify SSH access (no password prompt)

# Phase 3: Setup local SSH config (.31 deployment host)
#   ├─ Deploy all private keys to ~/.ssh/svc-keys/
#   ├─ Update ~/.ssh/config with PasswordAuthentication=no
#   ├─ Set SSH_ASKPASS=none in ~/.bashrc
#   └─ Verify no password prompts possible
```

### Step 3: Health Check (Automated Hourly)

```bash
# Verify all service account keys are working
bash scripts/ssh_service_accounts/health_check.sh

# For each service account:
#   ├─ Test SSH connectivity (no password prompt)
#   ├─ Verify SSH key permissions (600)
#   ├─ Check authorized_keys on target host
#   ├─ Log results to audit-trail.jsonl
#   └─ Alert on failure (Slack/email)
```

### Step 4: Key Rotation (Automated Monthly)

```bash
# Perform 90-day credential rotation on all keys
bash scripts/ssh_service_accounts/credential_rotation.sh

# For each service account:
#   ├─ Generate new Ed25519 key pair
#   ├─ Create new GSM version
#   ├─ Deploy new public key to authorized_keys
#   ├─ Keep old key for grace period (30 days)
#   ├─ After 30 days, remove old key
#   └─ Audit log all rotations
```

---

## Configuration Templates

### SSH Config Template (All Hosts)

```bash
# ~/.ssh/config - Service account configuration

# Global defaults - force key-only auth everywhere
Host *
    PasswordAuthentication no
    PubkeyAuthentication yes
    PreferredAuthentications publickey
    ChallengeResponseAuthentication no
    KbdInteractiveAuthentication no
    BatchMode yes
    ConnectTimeout 5

# On-premises infrastructure hosts
Host 192.168.168.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile ~/.ssh/svc-keys/*_key
    User svc-account

# Production host (.42)
Host 192.168.168.42 nexus-prod nexus-prod-primary
    HostName 192.168.168.42
    User svc-account
    IdentityFile ~/.ssh/svc-keys/nexus-deploy-automation_key
    IdentityFile ~/.ssh/svc-keys/nexus-k8s-operator_key

# NAS host (.39)
Host 192.168.168.39 nexus-nas nexus-backup-storage
    HostName 192.168.168.39
    User svc-account
    IdentityFile ~/.ssh/svc-keys/nexus-backup-manager_key
```

### Kubernetes ServiceAccount Template

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nexus-api-runner
  namespace: nexus-production
---
apiVersion: v1
kind: Secret
metadata:
  name: nexus-api-runner-ssh-keys
  namespace: nexus-production
type: Opaque
data:
  id_ed25519: <base64-encoded-private-key>
---
apiVersion: v1
kind: Pod
metadata:
  name: nexus-api-runner
  namespace: nexus-production
spec:
  serviceAccountName: nexus-api-runner
  containers:
  - name: nexus-api
    image: nexus-api:latest
    env:
    - name: SSH_ASKPASS
      value: "none"
    - name: SSH_ASKPASS_REQUIRE
      value: "never"
    - name: SSH_KEY_PATH
      value: "/run/secrets/ssh/id_ed25519"
    volumeMounts:
    - name: ssh-keys
      mountPath: /run/secrets/ssh
      readOnly: true
    - name: ssh-config
      mountPath: /home/appuser/.ssh
      readOnly: true
  volumes:
  - name: ssh-keys
    secret:
      secretName: nexus-api-runner-ssh-keys
      defaultMode: 0600
  - name: ssh-config
    configMap:
      name: ssh-config
      defaultMode: 0600
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    allowPrivilegeEscalation: false
```

---

## Access Control Matrix (RBAC)

| Role | Account | Hosts | Keys | Permissions | MFA |
|------|---------|-------|------|-------------|-----|
| Deployment Lead | nexus-deploy-automation | .42 | All deployment keys | Deploy, restart services | Yes |
| Platform Engineer | nexus-k8s-operator | .42 | Cluster ops keys | Modify K8s, node management | Yes |
| DevOps | nexus-terraform-runner | .42 | Terraform keys | Infra changes (with approval) | Yes |
| Build Engineer | nexus-docker-builder | .31, .42 | Build keys | Build, push images | No |
| CI/CD | nexus-ci-runner | .42 | CI keys | Test execution, artifact storage | No |
| Monitoring | nexus-prometheus-collector | .42 | Monitor keys | Read-only metrics | No |
| Security | nexus-secrets-manager | Cloud | Secrets keys | Manage all secrets | Yes |
| Compliance | nexus-compliance-reporter | .42 | Report keys | Generate reports | No |

---

## Monitoring & Alerting

### Service Account Health Dashboard

```yaml
# Create Prometheus alerts for SSH service accounts
groups:
- name: ssh_service_accounts
  rules:
  - alert: SSHKeyRotationOverdue
    expr: |
      (time() - ssh_key_last_rotation_timestamp) > (90 * 24 * 3600)
    for: 5m
    annotations:
      summary: "SSH key rotation overdue for {{ $labels.service_account }}"
      severity: "critical"

  - alert: SSHConnectionFailures
    expr: |
      rate(ssh_connection_failures_total[5m]) > 0.1
    for: 5m
    annotations:
      summary: "SSH connection failures for {{ $labels.service_account }}"
      severity: "high"

  - alert: PasswordPromptDetected
    expr: |
      ssh_password_prompt_detected_total > 0
    for: 1m
    annotations:
      summary: "SSH password prompt detected - security breach!"
      severity: "critical"

  - alert: UnauthorizedSSHKeyUsage
    expr: |
      ssh_key_used_from_unexpected_source > 0
    for: 1m
    annotations:
      summary: "SSH key {{ $labels.key_id }} used from unexpected source"
      severity: "critical"
```

---

## Operational Procedures

### Daily Operations

```bash
# 1. Check service account health
bash scripts/ssh_service_accounts/health_check.sh report

# 2. Verify SSH key-only enforcement
grep -r "SSH_ASKPASS=none" ~/.bashrc ~/.bash_profile
ssh -G 192.168.168.42 | grep -i password

# 3. Monitor audit log for anomalies
tail -f logs/audit-trail.jsonl | jq '.password_prompt'
```

### Weekly Operations

```bash
# 1. Review SSH connection patterns
jq '.target_host, .service_account' logs/audit-trail.jsonl | sort | uniq -c

# 2. Verify all keys present in GSM
gcloud secrets list --filter="labels.key_type=ssh-ed25519" --format="table(name)"

# 3. Check for failed deployments
grep "ERROR\|FAILED" logs/deployment-*.log
```

### Monthly Operations

```bash
# 1. Perform credential rotation
bash scripts/ssh_service_accounts/credential_rotation.sh full

# 2. Verify key distribution
for host in 192.168.168.42 192.168.168.39; do
    ssh root@$host "find /home -name authorized_keys -exec wc -l {} \;"
done

# 3. Generate compliance report
bash scripts/ssh_service_accounts/generate_compliance_report.sh
```

---

## Related Documentation

- [SSH_KEY_ONLY_MANDATE.md](../governance/SSH_KEY_ONLY_MANDATE.md) - Policy
- [SSH_10X_ENHANCEMENTS.md](../architecture/SSH_10X_ENHANCEMENTS.md) - Future roadmap
- [SERVICE_ACCOUNT_DEPLOYMENT_GUIDE.md](./SERVICE_ACCOUNT_DEPLOYMENT_GUIDE.md) - Manual setup
- [SSH_KEYS_ONLY_GUIDE.md](./SSH_KEYS_ONLY_GUIDE.md) - Implementation

---

**Status:** ✅ **ARCHITECTURE APPROVED**  
**Effective Date:** 2026-03-14  
**Service Accounts:** 32 total (3 legacy + 29 new)  
**All Using:** SSH Ed25519 keys + GSM storage + 90-day rotation
