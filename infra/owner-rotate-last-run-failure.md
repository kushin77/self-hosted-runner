# Owner Rotation Run Failure - 2026-03-12

Timestamp: 2026-03-12T00:45:46Z

Summary:

- Attempted to run `infra/owner-rotate-deployer-key-bootstrap.sh` (patched for prev_hash nounset).
- Script created a new service account key locally, but failed while trying to create the Secret Manager secret.

Error (excerpt):

```
ERROR: (gcloud.secrets.create) [deployer-run@nexusshield-prod.iam.gserviceaccount.com] does not have permission to access projects instance [nexusshield-prod] (or it may not exist): Permission 'secretmanager.secrets.create' denied for resource 'projects/nexusshield-prod'
```

Cause:

- The active credentials used to run the script are the `deployer-run` service account key that was created during the run. That account lacks `secretmanager.secrets.create` permission in project `nexusshield-prod`.

Next actions (recommended):

1. Run the bootstrap as a Project Owner (owner-level credentials) so the secret can be created, or grant `roles/secretmanager.admin` (or `roles/secretmanager.secretCreator`) to the principal that runs this script.
2. Alternatively, an Owner can pre-create the secret `deployer-sa-key` with automatic replication; then re-run the bootstrap (it will add a new secret version).
3. After successful creation, verify the audit file at `logs/multi-cloud-audit/` and then retire old secret versions as appropriate.

Action taken:

- The script was patched to avoid nounset failures in `log_audit()` and re-run; the failure is recorded here for traceability.
