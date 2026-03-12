Vault AppRole Rotation via Cloud Build
====================================

Overview
--------
This document explains how to run the Vault AppRole `secret_id` rotation using Cloud Build. The repo includes `cloudbuild/run-vault-rotation.yaml` which pulls the repo and runs `scripts/secrets/run_vault_rotation.sh` while supplying `VAULT_ADDR` and `VAULT_TOKEN` from Google Secret Manager.

Prerequisites
-------------
- Create Secret Manager secrets `VAULT_ADDR` and `VAULT_TOKEN` in the GSM project.
- Ensure the Cloud Build service account has `roles/secretmanager.secretAccessor` on those secrets.
- If rotating into GSM (the script stores the new AppRole secret_id into `vault-example-role-secret_id`), grant the Cloud Build service account `roles/secretmanager.secretAdmin` or a conservative role that allows `secrets.versions.add` on that specific secret.

Grant IAM (example commands)
----------------------------
Replace `PROJECT` with your GSM project and `BUILD_SA` with the Cloud Build service account (usually `PROJECT_NUMBER@cloudbuild.gserviceaccount.com`):

```bash
PROJECT=nexusshield-prod
BUILD_SA=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')@cloudbuild.gserviceaccount.com
gcloud secrets add-iam-policy-binding VAULT_ADDR --project="$PROJECT" --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor
gcloud secrets add-iam-policy-binding VAULT_TOKEN --project="$PROJECT" --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAccessor
gcloud secrets add-iam-policy-binding vault-example-role-secret_id --project="$PROJECT" --member=serviceAccount:$BUILD_SA --role=roles/secretmanager.secretAdmin
```

Run the Cloud Build
-------------------
Submit the build (substitute your GSM project):

```bash
gcloud builds submit --config=cloudbuild/run-vault-rotation.yaml --substitutions=_GSM_PROJECT=nexusshield-prod
```

What the build does
-------------------
- Clones the repo.
- Runs `scripts/secrets/run_vault_rotation.sh` which:
  - reads `VAULT_ADDR` and `VAULT_TOKEN` from Secret Manager
  - validates they're not placeholders
  - requests a new AppRole `secret_id` from Vault
  - stores the new `secret_id` as a new version in GSM secret `vault-example-role-secret_id`

If the build fails with placeholder detection, confirm the secrets `VAULT_ADDR` and `VAULT_TOKEN` contain real values and that the Build SA can access them.
