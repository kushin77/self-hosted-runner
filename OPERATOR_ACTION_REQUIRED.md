# Operator Action Required: Provision Deployment Secrets

This repository's auto-provisioning system requires production credential values to be populated in your credential providers or as GitHub repository secrets before Phase 2 validation can succeed.

Required fields (one or more providers can supply values):
- VAULT_ADDR — HashiCorp Vault server URL
- VAULT_ROLE — Vault role to assume / auth method
- AWS_ROLE_TO_ASSUME — AWS role ARN for cross-account access
- GCP_WORKLOAD_IDENTITY_PROVIDER — GCP Workload Identity Provider resource

Recommended steps (quick):
1. In your chosen provider console (GSM / Vault / AWS Secrets Manager), add the production secret values.
2. OR set them as GitHub Actions repository secrets:

```bash
gh secret set VAULT_ADDR --body "https://vault.example.internal"
gh secret set VAULT_ROLE --body "my-vault-role"
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::111222333444:role/ProvisionRole"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/123/locations/global/workloadIdentityPools/pool/providers/provider"
```

3. Run provisioning locally or in CI:

```bash
make -f Makefile.provisioning provision-fields
make -f Makefile.provisioning verify-provisioning
```

Audit trail: provisioning writes append-only JSONL to `logs/deployment-provisioning-audit.jsonl`.

If you want me to set placeholder secrets from environment variables I have access to, reply with `set-from-env` and I'll attempt it.

If you want me to create a GitHub issue for tracking, reply `create-issue`.
