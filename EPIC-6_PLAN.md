# EPIC-6: Cross-Cloud Integration

Goals:
- Expand multi-cloud credential orchestration to AWS and GCP managed identities
- Standardize runtime credential fetcher across providers (GSM → Vault → KMS)
- Add automated verification and smoke tests for cross-cloud flows

Steps:
1. Add AWS IAM role provisioning scripts and map to Vault/GSM
2. Add GCP service account bootstrap and IAM bindings
3. Add cross-cloud smoke tests and monitoring
4. Document runbook and rollback procedures

