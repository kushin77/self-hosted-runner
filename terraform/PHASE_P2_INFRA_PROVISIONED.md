# Phase 2: Infrastructure Provisioned (Automated)

The core security infrastructure for Vault has been provisioned in GCP project **gcp-eiq**.

## 1. Cloud Resources Created (via gcloud)
- **Service Account**: `vault-admin-sa@gcp-eiq.iam.gserviceaccount.com`
- **KMS Unseal Key**: `vault-unseal-key` in ring `vault-unseal-ring` (us-central1)
- **Storage Backend**: `gs://vault-data-gcp-eiq` (us-central1)

## 2. Workload Identity (OIDC) Setup
- **Workload Identity Pool**: `github-actions-pool-v3`
- **OIDC Provider**: `github-provider`
- **Trust Policy**: Configured to allow repository `elevatediq-ai/ElevatedIQ-Mono-Repo` to impersonate the Vault Service Account.

## 3. GitHub Actions Configuration
To use this in your workflow, use the following configuration for **google-github-actions/auth**:

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: "projects/1025559705580/locations/global/workloadIdentityPools/github-actions-pool-v3/providers/github-provider"
    service_account: "vault-admin-sa@gcp-eiq.iam.gserviceaccount.com"
```

## 4. Next Steps
- Execute the [infra-provision.yml](.github/workflows/infra-provision.yml) to verify end-to-end secret-less deployment.
- Initialize Vault using the configured GCS backend and KMS auto-unseal.
