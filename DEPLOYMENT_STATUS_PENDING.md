**Deployment Status — Pending**

- **Date:** 2026-03-11
- **Project:** nexusshield-prod
- **Status:** Blocked — insufficient IAM permissions for deploy service account

Summary:

The deployment automation (`scripts/deploy/direct_deploy.sh`) executed up to the Cloud Run step but failed with a permissions error:

```
PERMISSION_DENIED: Permission 'run.services.get' denied on resource 'namespaces/nexusshield-prod/services/nexusshield-portal-backend-production'
```

Active account: `nxs-portal-production-v2@nexusshield-prod.iam.gserviceaccount.com`

Required action (operator): grant the following IAM roles to the deploy identity, or provide a service account key with equivalent privileges.

- `roles/run.admin`
- `roles/iam.serviceAccountUser`
- `roles/cloudscheduler.admin`
- `roles/secretmanager.admin`
- `roles/cloudkms.cryptoKeyEncrypterDecrypter`
- `roles/storage.objectViewer`

Next steps I will perform after IAM is resolved or alternative credentials are provided:

1. Provision credentials into GSM/Vault/KMS using `scripts/credentials/provision_all_creds.sh` (idempotent). Requires env vars for secrets or operator input.
2. Run `scripts/deploy/direct_deploy.sh` to deploy Cloud Run and schedule health-check jobs.
3. Verify health-checks, alerts, and record audit entries to `logs/`.
4. Create and close a GitHub deployment status issue documenting success.

If you want me to rewrite git history to remove previously committed secrets (recommended), confirm and I'll prepare a safe plan using `git filter-repo`/BFG and rotation steps.
