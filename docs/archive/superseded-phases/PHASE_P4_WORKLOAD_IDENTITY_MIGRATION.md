## Phase P4 — Workload Identity Migration (recommended)

Purpose
- Provide guidance and a migration plan to replace instance metadata-based secret delivery with Workload Identity (recommended for production).

Why migrate
- Instance metadata injection is convenient for staging but exposes secrets in instance metadata and complicates rotation.
- Workload Identity avoids long-lived secrets on instances by allowing Kubernetes workloads or GCE VMs to exchange short-lived credentials with IAM-backed identities.

High-level plan (GCP-focused)

1. Create a dedicated service account for runners in each environment (staging/prod):

```hcl
resource "google_service_account" "runner" {
  account_id   = "runner-staging-a"
  display_name = "Runner service account (staging)"
}
```

2. Bind minimum IAM roles required (e.g., access to secrets in Secret Manager or Vault token bootstrap role).

3. Configure Workload Identity (for GKE):

- Create a Kubernetes service account and annotate it with the GCP service account:

```bash
kubectl create serviceaccount runner-sa -n runners
kubectl annotate serviceaccount runner-sa iam.gke.io/gcp-service-account=runner-staging-a@PROJECT.iam.gserviceaccount.com
```

4. Update bootstrap flow:

- Modify the startup/bootstrapper to use the metadata server or Workload Identity token exchange (GKE) instead of embedding Vault Agent config in metadata. For GCE VMs, prefer instance service accounts with limited scopes and an authenticated Vault auto-auth method (if supported).

5. Vault configuration

- Configure Vault auto_auth or auth method to accept the Workload Identity tokens or GCP IAM attestation. Example: enable `gcp` auth method in Vault and map roles to policies.

6. Rollout strategy

- Stage rollout in `staging` by deploying updated startup scripts and disabling `inject_vault_agent_metadata`.
- Validate token exchange and secret retrieval.
- Rotate/clean metadata entries and deprecate metadata injection flag after successful migration.

Monitoring & Security
- Monitor Vault login events and token renewals.
- Ensure least-privilege bindings and rotate keys where applicable.

Notes
- This document focuses on GCP/GKE; for AWS, consider IRSA (IAM Roles for Service Accounts) with EKS. For bare VMs, prefer short-lived instance tokens and an attestation-based Vault auth method.

References
- Vault GCP auth method: https://www.vaultproject.io/docs/auth/gcp
- GKE Workload Identity: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
