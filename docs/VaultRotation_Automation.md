Vault Rotation Automation — Setup Guide

Goal: Automatically run Vault AppRole rotation via Cloud Build on a schedule once real `VAULT_ADDR` and `VAULT_TOKEN` are provided.

What this repo provides:
- `cloudbuild/run-vault-rotation.yaml` — Cloud Build config that runs `scripts/secrets/run_vault_rotation.sh`.
- `scripts/secrets/run_vault_rotation.sh` — rotation script (reads secrets from GSM, validates placeholders, requests new secret_id, stores into GSM).
- `scripts/cloud/setup_vault_rotation_infra.sh` — idempotent helper to create Pub/Sub topic, grant IAM, and create Cloud Scheduler job (DRY-RUN by default).

Quick steps to enable automated rotation (operator):
1. Ensure GSM secrets exist and contain real values:
   - `VAULT_ADDR` (https://...)
   - `VAULT_TOKEN` (short-lived admin token or use AppRole provisioning flow)
2. Ensure Cloud Build service account can access those secrets and can write to the target secret (see script).
3. Run the infra setup script (dry-run shows commands):

```bash
# Dry-run
bash scripts/cloud/setup_vault_rotation_infra.sh

# To apply (create resources)
export APPLY=1
bash scripts/cloud/setup_vault_rotation_infra.sh
```

4. Confirm a subscriber exists for Pub/Sub topic `vault-rotation-trigger` which triggers the repository Cloud Build (the repo contains a Cloud Function bridge in `functions/`).
5. Test once manually:

```bash
gcloud builds submit --config=cloudbuild/run-vault-rotation.yaml --substitutions=_GSM_PROJECT=nexusshield-prod
```

Notes and best practices
- Do not store Vault admin tokens in the repository. Use Secret Manager and grant minimal access to the Build SA.
- Prefer short-lived tokens or AppRole creation flows; rotate AppRole `secret_id` on a schedule and store only role_id in GSM.
- Validate `VAULT_ADDR` is resolvable from Cloud Build (VPC access or public endpoint as appropriate).

If you want, I can apply the infra (create topic, IAM bindings, scheduler) now — say `APPLY=1` and I will run the setup script.