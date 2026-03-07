# Phase P4: Advanced Hardening & Multi-Tenancy — Runbook

This document describes deploying and operating Phase P4 hardening in production, including RBAC, network isolation, secret rotation, multi-tenancy, HA, and failover procedures.

## Prerequisites

- Phase P3 observability infrastructure deployed
- Kubernetes cluster with 3+ nodes
- Vault with AppRole auth method enabled
- Redis with persistence enabled
- kubectl configured for target cluster

## Component Overview

### 1. RBAC (Role-Based Access Control)

**Vault Policies** define who can provision infrastructure:
- `provisioner-admin` — Full access (administration)
- `provisioner-worker-org-${ORG}` — Per-org provisioning
- `managed-auth-role` — API request signing/validation
- `compliance-auditor` — Audit log read-only access

**Deployment:**
```bash
# Automatic via workflow
gh workflow run orchestrate-p4-hardening.yml -f environment=production

# Manual (if needed):
vault policy write provisioner-admin infrastructure/vault/rbac-policies.hcl
vault policy write provisioner-worker-org-github-actions \
  <(sed 's/{{ .org_name }}/github-actions/g' infrastructure/vault/rbac-policies.hcl)
```

**Verification:**
```bash
vault policy list
vault policy read provisioner-worker-org-github-actions
```

### 2. Network Isolation

**Kubernetes NetworkPolicies** enforce zero-trust network access:
- provisioner-worker: Can only reach Redis and Vault
- managed-auth: Can only reach Vault and provisioner-worker
- Redis: Only accessible from provisioner-worker and managed-auth
- All: Deny all ingress by default

**Deployment:**
```bash
kubectl apply -f infrastructure/kubernetes/network-policies.yaml
```

**Verification:**
```bash
# List all network policies
kubectl get networkpolicies -n provisioner-system

# Test connectivity (should fail):
kubectl run debug --image=busybox -it --rm -- \
  wget -O- http://provisioner-worker.provisioner-system:3000/

# Should fail with "connection refused" (good!)
```

### 3. mTLS (Mutual TLS)

**mTLS secures provisioner-worker ↔ Vault communication:**
- Auto-generated server certificate (CN: provisioner-worker.provisioner-system.svc.cluster.local)
- Auto-generated client certificate (for Vault to verify)
- CA-signed certificates
- Certificates refreshed yearly (idempotent)

**Deployment:**
```bash
bash scripts/setup-mtls.sh
```

**Verification:**
```bash
# Check Kubernetes secrets
kubectl describe secret provisioner-worker-tls -n provisioner-system

# Verify certificate validity (30+ days remaining)
openssl x509 -in /etc/provisioner-worker/certs/server.crt -text -noout | grep -A2 "Validity"
```

### 4. Secret Rotation

**AppRole secrets refreshed automatically:**
- Rotation schedule: Weekly (configurable)
- New secret_id generated
- Kubernetes secret updated
- Pods rolling-restarted
- Old secrets revoked (optional, manual review)
- Vault audit log entry created

**Manual Rotation:**
```bash
bash scripts/rotate-vault-secrets.sh

# Or via workflow:
gh workflow run rotate-vault-secrets.yml -f vault_role=provisioner-worker-role
```

**Verification:**
```bash
# Check last secret_id generation
vault list auth/approle/role/provisioner-worker-role/secret-id

# Verify Vault audit logging
tail -20 /vault/logs/audit.log | grep "secret_id"
```

### 5. Multi-Tenancy

**Multi-organization support with per-org isolation:**

#### Adding a New Organization

1. **Create Vault policy for org:**
   ```bash
   export ORG_NAME="my-org"
   vault policy write provisioner-worker-org-${ORG_NAME} \
     <(sed "s/{{ .org_name }}/${ORG_NAME}/g" infrastructure/vault/rbac-policies.hcl)
   ```

2. **Create AppRole for org:**
   ```bash
   vault write auth/approle/role/provisioner-worker-org-${ORG_NAME} \
     policies="provisioner-worker-org-${ORG_NAME}" \
     bind_secret_id=true
   
   # Capture role_id and secret_id for service configuration
   vault read -field=role_id auth/approle/role/provisioner-worker-org-${ORG_NAME}
   vault write -field=secret_id auth/approle/role/provisioner-worker-org-${ORG_NAME}/secret-id
   ```

3. **Configure Terraform module for org** (in `modules/runner/` or per-org subdirectory):
   ```hcl
   # modules/runner/${ORG_NAME}/main.tf
   # Per-org Terraform configuration: instance counts, labels, cost tracking, etc.
   ```

4. **Setup cost tracking ConfigMap:**
   ```bash
   kubectl create configmap provisioner-org-${ORG_NAME}-config \
     --from-literal=cost_center="billing-${ORG_NAME}" \
     --from-literal=runner_labels="self-hosted,${ORG_NAME}" \
     -n provisioner-system
   ```

#### Handling Multi-Org Requests

The provisioner-worker validates each provisioning request:
1. Verifies org_id in request signature (HMAC-SHA256)
2. Checks org-specific Vault policy
3. Loads per-org Terraform module
4. Tracks cost per-org in Redis timeseries
5. Logs audit trail with org context

**Example Request (programmatic):**
```bash
ORG_NAME="my-org"
ORG_SECRET="secret-shared-with-org"

# Create request body
REQUEST_BODY=$(cat << EOF
{
  "org_name": "$ORG_NAME",
  "runners_count": 3,
  "runner_labels": ["self-hosted", "linux"],
  "terraform_vars": {
    "instance_type": "t3.medium",
    "ami_id": "ami-0c55b159cbfafe1f0"
  }
}
EOF
)

# Sign request with org secret
SIGNATURE=$(echo -n "$REQUEST_BODY" | openssl dgst -sha256 -hmac "$ORG_SECRET" -r | cut -d' ' -f1)

# Submit to managed-auth API
curl -X POST https://managed-auth.example.com/provision \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY" \
  -H "X-Signature: $SIGNATURE"
```

### 6. High Availability & Failover

**3-replica deployment with Redis coordination:**
- **Query**: `kubectl get deployment provisioner-worker-ha -n provisioner-system`
- **Scale**: `kubectl scale deployment provisioner-worker-ha --replicas=5 -n provisioner-system`

#### Graceful Shutdown (Automatic)

When a pod is terminated:
1. `preStop` hook runs `/app/scripts/graceful-shutdown.sh`
2. Worker stops accepting new jobs
3. Wait up to 60s for current jobs to complete
4. Incomplete jobs requeued to Redis
5. Vault token revoked
6. Process exits cleanly

**Monitor graceful shutdown:**
```bash
kubectl logs -f <pod-name> -n provisioner-system | grep "shutdown"
```

#### Manual Failover Test

```bash
# 1. Identify a worker pod
POD=$(kubectl get pods -l app=provisioner-worker-ha -n provisioner-system -o name | head -1)

# 2. Delete it (triggers graceful shutdown)
kubectl delete $POD -n provisioner-system

# 3. Monitor job requeuing
kubectl logs -f $POD -n provisioner-system | tail -20

# 4. Verify new pod starts automatically
kubectl get pods -l app=provisioner-worker-ha -n provisioner-system

# New pod should start within 10 seconds
```

#### Recovery from Pod Crash

If a pod crashes (kills without graceful shutdown):
1. Kubernetes restarts it automatically (liveness probe)
2. On startup, provisioner-worker checks for jobs in `provisioner:jobs:active`
3. Any incomplete jobs from crashed pod are marked and requeued
4. Service continues without operator intervention

**Monitor crashes:**
```bash
kubectl describe pod <pod-name> -n provisioner-system | grep -A5 "Last State"
```

### 7. Compliance & Auditing

**All provisioning actions are audited:**
- Vault audit log (JSON format, queryable)
- Kubernetes event log (audit-webhook)
- Cost tracking per-org (Redis timeseries)
- Request signatures logged for compliance

**Access audit trail:**
```bash
# Query Vault audit log for org-specific actions
grep "provisioner-worker-org-github-actions" /vault/logs/audit.log | jq '.request.path'

# Track cost per-org
redis-cli ZRANGE metrics:provisioner:cost:github-actions 0 -1 WITHSCORES

# View Kubernetes audit events
kubectl get events -n provisioner-system --sort-by='.lastTimestamp'
```

## Deployment Checklist

- [ ] Vault RBAC policies created for all orgs
- [ ] Kubernetes NetworkPolicies applied
- [ ] mTLS certificates generated and deployed
- [ ] Secret rotation scheduled (cron weekly)
- [ ] Multi-tenant configs loaded for all orgs
- [ ] HA deployment (3+ replicas) running
- [ ] Pod Disruption Budget enforced (minAvailable: 2)
- [ ] Health endpoints verified (GET /health, /ready)
- [ ] Cost tracking enabled per-org
- [ ] Audit logging active

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod <pod-name> -n provisioner-system
kubectl logs <pod-name> -n provisioner-system --previous
```

### Network Policy Blocking Traffic

```bash
# Temporarily disable (NOT for production):
kubectl delete networkpolicies --all -n provisioner-system

# Re-apply:
kubectl apply -f infrastructure/kubernetes/network-policies.yaml
```

### Vault Authentication Failed

```bash
# Check AppRole secret validity
vault list auth/approle/role/provisioner-worker-role/secret-id

# Verify Vault reachability from pod
kubectl exec -it <pod-name> -n provisioner-system -- \
  curl -k https://vault.vault.svc.cluster.local:8200/v1/sys/health
```

### Jobs Stuck in Queue

```bash
# Check Redis queue
redis-cli LLEN provisioner:jobs:queue
redis-cli LRANGE provisioner:jobs:queue 0 10

# Check for stuck jobs
redis-cli HGETALL provisioner:jobs:active

# Manually requeue (caution):
JOBS=$(redis-cli HVALS provisioner:jobs:active)
for job in $JOBS; do
  redis-cli RPUSH provisioner:jobs:queue "$job"
done
redis-cli DEL provisioner:jobs:active
```

## Rollback

If P4 hardening causes issues:

1. **Keep P3 deployment running** (no breaking changes)
2. **Disable network policies** (if blocking traffic):
   ```bash
   kubectl delete networkpolicies --all -n provisioner-system
   ```
3. **Revert to P3 image** (if needed):
   ```bash
   kubectl set image deployment/provisioner-worker \
     worker=<p3-image>:latest -n provisioner-system
   ```
4. **Disable RBAC** (revert to simple auth):
   - Manually set AppRole policies back to `default`
5. **Resume P3 operation** and file incident report

---

**Status**: P4 hardening is fully automated, idempotent, and production-ready.

For questions, refer to GitHub issue #148.
