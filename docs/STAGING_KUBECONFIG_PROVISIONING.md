# STAGING_KUBECONFIG Provisioning Runbook

Purpose
-------
This runbook describes how to provision a least-privileged kubeconfig for the `staging` cluster, store it securely (GSM or Vault), and wire it into CI for server-side validation and optional smoke tests.

Security principles
-------------------
- Immutable: store only base64-encoded kubeconfig in secret manager; audit changes.
- Ephemeral: prefer short-lived tokens or rotate credentials frequently.
- Idempotent: provisioning scripts are safe to run multiple times.
- No-ops: automations perform the work — operator only provisions secrets.

Steps (GSM / GCP Secret Manager)
--------------------------------
1. Create a service account in the cluster (kube-side) with RBAC limited to `runners` namespace and resources: `networkpolicies`, `scaledobjects.keda.sh`, `configmaps`.
2. Generate kubeconfig for the service account and verify access from a test machine.
3. Base64-encode the kubeconfig:

```bash
base64 -w0 kubeconfig.yaml > kubeconfig.b64
```

4. Store in GCP Secret Manager:

```bash
gcloud secrets create STAGING_KUBECONFIG --replication-policy="automatic"
gcloud secrets versions add STAGING_KUBECONFIG --data-file=kubeconfig.b64
```

5. Create a short-lived GCP service account key for CI to fetch secrets, store its JSON in the repository secrets manager as `GCP_SA_KEY` and set `GCP_PROJECT`.

Steps (HashiCorp Vault)
------------------------
1. Write kubeconfig to Vault at `secret/staging` with key `STAGING_KUBECONFIG` (value base64-encoded).

```bash
vault kv put secret/staging STAGING_KUBECONFIG=@kubeconfig.b64
```

2. Configure Vault auth for CI (OIDC/approle) and provide short-lived tokens to runners.

CI Wiring
---------
- The PR workflow supports:
  - GSM: `GCP_PROJECT`, `GCP_SA_KEY`
  - Vault: `VAULT_ADDR`, `VAULT_ROLE` (with CI login configured)
  - Repo secret fallback: `STAGING_KUBECONFIG` (base64)

Verification
------------
1. Open a test PR; confirm the workflow fetches kubeconfig and posts a comment about the backend used.
2. Confirm `kubectl apply --dry-run=server` runs successfully for a sample policy.

Rotation and audit
------------------
- Rotate service account credentials regularly and update secret versions.
- Use audit logs (GSM/Vault) to track access.

Contact
-------
Assign to: @ops, @platform-security
