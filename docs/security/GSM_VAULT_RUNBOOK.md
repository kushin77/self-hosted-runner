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

## 4. Operational Recommendations (Actions to Add)

To make GSM+Vault integration operationally robust and auditable, add the following sections to this runbook and implement their guidance.

### 4.1 Least-Privilege IAM Roles

- Define minimal IAM roles for each service account rather than granting broad roles. Example roles:
	- `roles/secretmanager.secretAccessor` — for processes that only need to read secret versions.
	- `roles/cloudkms.cryptoKeyEncrypterDecrypter` — for KMS operations limited to the unseal key crypto key.
	- `roles/storage.objectAdmin` (scoped to the Vault storage bucket) — only for Vault maintenance jobs (avoid on runner identities).
- Document which service account uses each role and store mapping here.

### 4.2 Secret Lifecycle & Rotation

- Maintain an explicit rotation policy for long-lived GSM secrets (e.g., service account JSON, unseal recovery keys):
	- **Rotation cadence**: 90 days for credentials, immediate for suspected compromise.
	- **Automation**: Provide CI jobs that rotate GSM secrets and update dependent Vault config or ADC consumers.
	- **Version management**: Use secret version labeling and an automated promotion procedure (test → canary → active).

### 4.3 CMEK and Key Management

- Use Customer-Managed Encryption Keys (CMEK) for GSM and GCS buckets where supported. Restrict key IAM to a small admin group and the Vault KMS principal.
- Enforce KMS key rotation and document the key rotation runbook and rollback procedure.

### 4.4 Emergency Compromise Playbook

- Prepare a short, actionable incident playbook:
	1. Revoke compromised service account keys and remove IAM bindings.
	2. Rotate the affected GSM secret(s) and verify dependent systems (Vault, runners) can fetch new versions.
	3. If Vault unseal keys are suspected, follow Vault rekey/rotate procedure and restore from backup if needed.
	4. Notify stakeholders and open an incident in the tracker with assigned responders.

### 4.5 Auditing & Alerting

- Configure Cloud Logging alerts for the following events and retain logs per compliance needs:
	- `secretmanager.v1.AccessSecretVersion` failures or suspicious access patterns.
	- `cloudkms.cryptoKeyVersions.use` events for the unseal key outside known maintenance windows.
	- Vault `sys/auth` failures and `sys/audit` entries indicating AppRole creation or deletion.
- Provide example alert rules (Cloud Monitoring) and notification channels (PagerDuty/Slack).

### 4.6 Workload Identity Binding & Audit

- Document the exact steps to create and bind Workload Identity pools and provider mappings for runner workloads.
- Enforce short-lived tokens and audit mappings by exporting the Workload Identity binding list periodically.

### 4.7 Backup & Restore for Vault Data

- Regularly back up the Vault storage bucket (GCS) and test restores on a dedicated restore environment:
	- `gsutil cp -r gs://vault-data-<PROJECT_ID> /tmp/vault-backup-$(date +%F)`
	- Restore verification: start a test Vault instance and validate data integrity and unseal flow.

### 4.8 CI/Testing & Validation

- Add periodic CI smoke-tests that validate GSM access from the control host and that Vault auto-unseal works end-to-end.
- Add a pre-flight check job that verifies required GSM secret versions and KMS key permissions before production deployments.

### 4.9 Replication and Region Strategy

- Document whether GSM secrets and the GCS backend are multi-region or single-region and the implications for disaster recovery and latency.

## 5. Example Commands and Playbooks

Below are short example commands and snippets referenced in the operational sections above.

### 5.1 Check GSM secret access (example)

```bash
gcloud secrets versions access latest --secret=projects/${PROJECT}/secrets/<SECRET_NAME>
```

### 5.2 Backup Vault storage bucket (example)

```bash
gsutil -m rsync -r gs://vault-data-${PROJECT} /backup/vault-data-${PROJECT}-$(date +%F)
```

### 5.3 Rotate a service account key (example)

```bash
gcloud iam service-accounts keys create /tmp/new-key.json --iam-account svc-account@${PROJECT}.iam.gserviceaccount.com
# update GSM with the new key file and retire the old version
```

## 6. Contacts & Owners

- **Security Lead**: ops-security@your-org.example (owner for KMS/GSM policies)
- **Vault Admin**: vault-admins@your-org.example
- **On-call**: ops-oncall@your-org.example

---

*Last updated: automated patch — add operational guidance and examples.*
