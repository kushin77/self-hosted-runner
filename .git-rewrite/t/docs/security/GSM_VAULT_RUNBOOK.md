# GCP Secret Manager (GSM) & Vault Integration Runbook

This runbook describes the integration between Google Secret Manager (GSM) and HashiCorp Vault within the ElevatedIQ ecosystem.

## 1. Overview
We utilize **GCP Secret Manager** for root-of-trust secrets and **HashiCorp Vault** for dynamic, ephemeral, and fine-grained secret management.

- **GSM**: Stores highly sensitive, long-lived credentials (e.g., Vault unseal keys, service account JSON).
- **Vault**: Integrated with GCP KMS for auto-unseal and Workload Identity for auth.

## 2. Integration Pattern

### A. Auto-Unseal with GCP KMS
Vault is configured to automatically unseal using a dedicated GCP KMS key.
- **Key Ring**: `vault-unseal-ring`
- **Crypto Key**: `vault-unseal-key`

### B. Storage Backend
Vault uses **Google Cloud Storage (GCS)** as its persistent storage backend.
- **Bucket**: `vault-data-<PROJECT_ID>`

### C. Authentication (Workload Identity)
All runner workloads authenticate to Vault using **GCP Workload Identity**.
- Applications present a signed JWT to Vault's `auth/gcp` backend.
- No static secrets are stored in the application environment.

## 3. Operations & Maintenance

### Rotating IAM Credentials
1. Update the Service Account in GCP.
2. If using static keys (deprecated), update the secret in GSM.
3. Vault will automatically pick up the new role bindings.

### Monitoring Security
- Audit logs from both GSM and Vault are streamed to Cloud Logging.
- Alerts are triggered on `sys/auth` failures and `secretmanager.v1.SecretManagerService.AccessSecretVersion` failures.

---
*Created by Security Master (Automated Audit Rollout)*
