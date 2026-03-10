# Vault Automation (Overview)

This document describes an opinionated, idempotent approach to deploy HashiCorp Vault and keep secrets synchronized with Google Secret Manager (GSM).

Goals:
- Immutable deploys: use Helm `upgrade --install` for immutable releases.
- Ephemeral: Vault storage is backed by durable storage (GCS or PersistentVolumes) and auto-unseal via KMS.
- Idempotent: scripts are `upgrade --install` and safe to re-run.
- No-GitHub-Actions: use on-host orchestration or internal CI runner for automation.

Quickstart (operator):

1. Ensure a Kubernetes cluster and `kubectl` configured.
2. Ensure a KMS key exists (we use `google_kms_crypto_key` from Terraform). Provide project/ring/key to the deploy script.

Deploy Vault:

```bash
./scripts/vault/deploy_vault.sh vault my-gcp-project my-key-ring my-key-name
```

Sync a secret from GSM to Vault:

```bash
./scripts/vault/sync_gsm_to_vault.sh my-gsm-secret vault/data/my-app/creds
```

Notes:
- The scripts assume `gcloud` and `vault` CLIs are present and authenticated.
- For automation, run these scripts from a secure runner with appropriate service account access.
