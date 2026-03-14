# SSO Platform - TIER 1: Security Hardening Implementation Guide

## Overview

TIER 1 security hardening establishes a production-grade, zero-trust foundation for the SSO platform. This guide covers network isolation, access control, secrets management, and database reliability.

## Components

### 1. Network Policies (Zero-Trust Networking)

**File**: `infrastructure/sso/5-network-policies.yaml`

#### What It Does
- Implements default-deny ingress and egress for all pods
- Creates explicit allow rules only for required traffic paths
- Isolates namespaces from cross-namespace communication
- Permits DNS and metrics scraping

#### Key Policies
```
OAuth2-Proxy  →  Keycloak  (port 8080)
Keycloak      →  PostgreSQL (port 5432)
PostgreSQL    →  PostgreSQL (replication)
Prometheus    →  All Services (metrics on 9090, 8008, 3200)
All           →  DNS (port 53)
```

#### Deployment
```bash
kubectl apply -f infrastructure/sso/5-network-policies.yaml
kubectl get networkpolicy -n keycloak
```

#### Verification
```bash
# Test connectivity between pods
kubectl run -it --rm debug --image=busybox --restart=Never -n keycloak -- \
  wget -O- http://keycloak:8080/auth/health

# Verify cross-namespace traffic is blocked
kubectl run -it --rm debug --image=busybox --restart=Never -n default -- \
  wget -O- http://keycloak:8080/auth/health # Should timeout
```

### 2. RBAC (Role-Based Access Control)

**File**: `infrastructure/sso/7-rbac.yaml`

#### What It Does
- Creates service accounts with minimal required permissions
- Defines cluster/namespace roles for each component
- Isolates pod-to-API-server access
- Enables full audit trail of API operations

#### Service Accounts
- `keycloak` - Core identity provider service account
- `keycloak-postgres` - Database operator and Patroni orchestration
- `oauth2-proxy` - Token validation gateway

#### Key Bindings
```
keycloak        → Read ConfigMaps, Secrets
keycloak-postgres → Manage StatefulSets, Endpoints
oauth2-proxy    → Read ConfigMaps, Secrets
```

#### Deployment
```bash
kubectl apply -f infrastructure/sso/7-rbac.yaml
kubectl get serviceaccount -n keycloak
kubectl get clusterrole | grep keycloak
```

#### Verification
```bash
# List all RBAC bindings
kubectl get rolebinding -n keycloak
kubectl get clusterrolebinding | grep keycloak

# Test authorization (should be denied)
kubectl auth can-i get pods --as=system:serviceaccount:keycloak:keycloak -n oauth2-proxy
```

### 3. PostgreSQL High Availability

**File**: `infrastructure/sso/2b-keycloak-postgres-ha.yaml`

#### What It Does
- Upgrades from 1-node to 3-node StatefulSet
- Implements Patroni for automatic failover
- Configures streaming replication with WAL archiving
- Enables connection pooling and backup support

#### Architecture
```
PostgreSQL Cluster (3 replicas):
├── Node 0 (Primary)    [Read/Write]
├── Node 1 (Standby)    [Read-only + Failover candidate]
└── Node 2 (Standby)    [Read-only + Failover candidate]

Patroni DCS: Distributed Consensus Store for leader election
```

#### Key Features
- **Automatic Failover**: <30 seconds to promote standby
- **Streaming Replication**: ~0ms lag with synchronous mode
- **Self-Healing**: Auto-recovery on node crash
- **Connection Limits**: 200 max connections, 10 max replication slots

#### Deployment
```bash
kubectl apply -f infrastructure/sso/2b-keycloak-postgres-ha.yaml
kubectl get statefulset -n keycloak keycloak-postgres
kubectl get pods -n keycloak -l app=keycloak-postgres
```

#### Verification
```bash
# Check primary/standby roles
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak -c "SELECT usename, application_name, client_addr, state FROM pg_stat_replication;"

# Monitor replication lag
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak -c "SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```

### 4. Pod Security Standards

**File**: `infrastructure/sso/9-pod-security-standards.yaml`

#### What It Does
- Enforces restricted Pod Security Policy cluster-wide
- Blocks privileged containers
- Requires non-root users (keycloak:1000, postgres:999)
- Implements OpenPolicyAgent Gatekeeper for policy-as-code
- Enforces resource requests/limits

#### Policies Enforced
```yaml
✅ Privileged: false
✅ AllowPrivilegeEscalation: false
✅ RunAsNonRoot: true
✅ RequiredDropCapabilities: [ALL]
✅ ReadOnlyRootFilesystem: enforced for stateless components
✅ ResourceLimits: CPU + Memory required
```

#### Deployment
```bash
kubectl apply -f infrastructure/sso/9-pod-security-standards.yaml
kubectl get psp restricted-psp
kubectl get constraints.gatekeeper.sh
```

#### Verification
```bash
# Try creating a privileged pod (should be denied by PSP/Gatekeeper)
kubectl run --rm -it --image=busybox --privileged test -- sh

# Check policy violations
kubectl describe constraint k8srequiredlabels
```

### 5. GSM/KMS Vault Integration

**File**: `infrastructure/sso/10-gke-credentials-vault.yaml`
**Script**: `scripts/sso/setup-gsm-integration.sh`

#### What It Does
- Integrates Google Secret Manager for credential storage
- Uses Cloud KMS for envelope encryption
- Implements Workload Identity for pod authentication
- Enables automatic secret injection via CSI driver
- Supports automatic credential rotation

#### Architecture
```
Pod (Keycloak/OAuth2-Proxy)
    ↓
Workload Identity (pod SA → GCP SA)
    ↓
Google Secret Manager (encrypted with KMS)
    ↓
CSI Secret Store Provider (injects as env vars)
```

#### Setup
```bash
./scripts/sso/setup-gsm-integration.sh nexus-prod us-central1

# This script:
# 1. Creates KMS keyring and encryption key
# 2. Creates GSM secrets for all credentials
# 3. Sets up Workload Identity bindings
# 4. Configures CSI SecretStore
# 5. Grants necessary IAM roles
```

#### Verification
```bash
# Check Workload Identity binding
kubectl describe sa gke-workload-identity-keycloak -n keycloak

# Verify GSM secret access
gcloud secrets list --project=nexus-prod

# Test credential injection
kubectl exec -it keycloak-0 -n keycloak -- env | grep DB_PASSWORD
```

### 6. Backup & Disaster Recovery

**Script**: `scripts/sso/backup-restore-procedures.sh`

#### Features
- **Daily Automated Backups**: 1:00 AM UTC to GCS
- **Backup Retention**: 30 days by default (configurable)
- **Point-in-Time Recovery**: With WAL archiving
- **Backup Verification**: Integrity checks on restore

#### Backup Management
```bash
# Create manual backup
./scripts/sso/backup-restore-procedures.sh backup

# Enable daily automated backups
./scripts/sso/backup-restore-procedures.sh enable-daily

# List available backups
./scripts/sso/backup-restore-procedures.sh list

# Restore from specific backup
./scripts/sso/backup-restore-procedures.sh restore keycloak_backup_20260314_010000.sql.gz
```

## Deployment Sequence

### Phase 1: Pre-flight Checks (2 min)
```bash
# Verify cluster connectivity
kubectl cluster-info

# Check node status
kubectl get nodes

# Verify RBAC permissions
kubectl auth can-i create networkpolicy --as=system:serviceaccount:keycloak:keycloak
```

### Phase 2: Deploy TIER 1 Manifests (5 min)
```bash
# Network isolation first
kubectl apply -f infrastructure/sso/5-network-policies.yaml
sleep 30

# RBAC setup
kubectl apply -f infrastructure/sso/7-rbac.yaml

# Pod security
kubectl apply -f infrastructure/sso/9-pod-security-standards.yaml

# Secrets vault
kubectl apply -f infrastructure/sso/10-gke-credentials-vault.yaml

# Database HA
kubectl apply -f infrastructure/sso/2b-keycloak-postgres-ha.yaml
```

### Phase 3: Setup GCP Resources (3 min)
```bash
./scripts/sso/setup-gsm-integration.sh nexus-prod us-central1
```

### Phase 4: Configure Backups (2 min)
```bash
./scripts/sso/backup-restore-procedures.sh enable-daily
```

### Phase 5: Verification (5 min)
```bash
# All pods running
kubectl get pods -n keycloak
kubectl get pods -n oauth2-proxy

# Network policies enforced
kubectl get networkpolicy -n keycloak
kubectl get psp

# RBAC configured
kubectl get clusterrole | grep keycloak
kubectl get rolebinding -n keycloak

# Secrets vault working
gcloud secrets list
```

## Security Best Practices

### Network Isolation
✅ Default-deny egress/ingress
✅ Explicit allow rules only
✅ Pod-to-pod mTLS ready (Istio compatible)
✅ Cross-namespace traffic blocked

### Access Control
✅ Service accounts with minimal scope
✅ Pod-level RBAC enforcement
✅ No admin credentials in pods
✅ Audit logging of all API operations

### Secrets Management
✅ Zero hardcoded secrets
✅ End-to-end encryption (KMS)
✅ Workload identity for authentication
✅ Automatic rotation support

### Data Protection
✅ PostgreSQL replication
✅ Automated backups to GCS
✅ Point-in-time recovery
✅ 30-day retention by default

## Troubleshooting

### Network Policy Issues
```bash
# Check if network policies are blocking traffic
kubectl get networkpolicy -n keycloak -o wide

# Temporarily disable a policy for debugging
kubectl delete networkpolicy deny-all -n keycloak

# Re-enable after testing
kubectl apply -f infrastructure/sso/5-network-policies.yaml
```

### RBAC Denials
```bash
# Check what permissions a service account has
kubectl auth can-i list pods --as=system:serviceaccount:keycloak:keycloak

# Review role bindings
kubectl get rolebinding -n keycloak -o yaml | grep keycloak

# Add missing permissions (if needed)
kubectl apply -f infrastructure/sso/7-rbac.yaml
```

### PostgreSQL HA Issues
```bash
# Check replication status
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak -c "SELECT * FROM pg_stat_replication;"

# Force failover if primary is stuck
kubectl delete pod keycloak-postgres-0 -n keycloak

# Verify standby promotion
kubectl get pods -n keycloak keycloak-postgres-0
```

### Secrets Vault Access Denied
```bash
# Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy sso-keycloak@nexus-prod.iam.gserviceaccount.com

# Check pod can authenticate
kubectl exec -it keycloak-0 -n keycloak -- \
  gcloud auth list

# Verify GSM secret exists
gcloud secrets describe keycloak-db-password --project=nexus-prod
```

## Monitoring & Compliance

### Security Metrics
- ✅ Pod Security Policy violations: 0
- ✅ RBAC denial count: Track and review
- ✅ Network policy drops: Monitor egress failures
- ✅ Failed authentication attempts: Alert threshold > 10/min

### Compliance Checkpoints
- ✅ Non-root user enforcement: Every pod
- ✅ Secret encryption: Every credential
- ✅ Backup existence: Daily verification
- ✅ RBAC audit trail: 90-day retention

## Next Steps

After TIER 1 is deployed:
1. Proceed to TIER 2: Observability (Tempo, Grafana, autoscaling)
2. Implement TIER 3: Compliance (audit exports, GDPR procedures)
3. Optional: TIER 4 (legacy integration) and TIER 5 (developer tools)

---

**Last Updated**: 2026-03-14
**Version**: 1.0.0
**Status**: Production Ready
