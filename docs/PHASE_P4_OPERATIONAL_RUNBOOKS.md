# PHASE P4: Operational Runbooks (Security & Scaling)

## Table of Contents
1. [KEDA Autoscaling (P4.1)](#1-keda-autoscaling-p41)
2. [Workload Identity (P4.2)](#2-workload-identity-p42)
3. [Vault Token Lifecycle (P4.3)](#3-vault-token-lifecycle-p43)
4. [Emergency Multi-Tenant Isolation](#4-emergency-multi-tenant-isolation)

---

## 1. KEDA Autoscaling (P4.1)

### Overview
Automated scaling of GitHub Runner pods based on Prometheus metrics (Pending Jobs).

### Troubleshooting Scaling Issues

#### Issue: Runners not scaling up during peak load
**Symptoms**: High queue depth in GitHub, but no new pods in `arc-runners` namespace.
**Check**:
```bash
# 1. Check ScaledObject status
kubectl get scaledobject -n arc-runners

# 2. Check KEDA operator logs
kubectl logs -l app=keda-operator -n keda

# 3. Verify Prometheus metric
# Query: gh_runner_busy_count / gh_runner_total_count
```
**Resolution**:
- Ensure the `Prometheus` trigger metadata points to the correct endpoint.
- Verify `STAGING_KUBECONFIG` has permissions to list pods in the target namespace.

---

## 2. Workload Identity (P4.2)

### Overview
Securely mapping GKE Service Accounts to GCP IAM Service Accounts without static keys.

#### Issue: "Access Denied" when runner tries to access GCR/Vault
**Symptoms**: `PermissionDenied` errors in runner initialization logs.
**Check**:
```bash
# 1. Verify SA mapping
kubectl get sa runner-sa -o yaml | grep "iam.gke.io/gcp-service-account"

# 2. Test identity from within a pod
gcloud auth list
```
**Resolution**:
- Re-run Terraform module `workload-identity` to ensure IAM bindings are present.
- Ensure the GSA has the `roles/iam.workloadIdentityUser` role for the KSA.

---

## 3. Vault Token Lifecycle (P4.3)

### Overview
Automatic renewal of Vault tokens via `systemd` and `vault-renewal.sh`.

#### Issue: Vault tokens expiring (403 Forbidden)
**Symptoms**: Runners fail to fetch secrets; `vault-renewal.service` shows "Failed".
**Check**:
```bash
# 1. Check systemd service status
systemctl status vault-renewal.service

# 2. View renewal logs
journalctl -u vault-renewal.service -n 50
```
**Resolution**:
- Manually trigger renewal: `scripts/identity/vault-renewal.sh`.
- If OIDC login fails, check if the instance metadata still contains a valid JWT.

---

## 4. Emergency Multi-Tenant Isolation

### Overview
Quickly isolating a compromised tenant or runner pool.

**Action**:
1. **Scale to Zero**: 
   ```bash
   kubectl patch scaledobject [tenant-name] -p '{"spec":{"minReplicaCount":0, "maxReplicaCount":0}}'
   ```
2. **Revoke Vault Access**:
   ```bash
   vault token revoke -mode path auth/oidc/role/[tenant-role]
   ```
