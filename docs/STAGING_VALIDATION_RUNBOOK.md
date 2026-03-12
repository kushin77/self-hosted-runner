Staging Validation Runbook — Signing & GSM/Vault/KMS

Purpose
-------
Steps and prerequisites to validate that signing and secret retrieval work in staging.

Prerequisites
- `gcloud` CLI authenticated with a service account that has `roles/secretmanager.secretAccessor` for the signing secret and `roles/storage.objectCreator` for the signature bucket.
- Optional: `openssl` installed for verification steps.
- Repo checkout with `scripts/signing/sign_artifact.sh` and `scripts/validation/staging_signing_validate.sh`.

Environment variables / inputs
- `_SIGNING_SECRET_NAME` — name of GSM secret storing the private key (PEM).
- `_ARTIFACT_PATH` — path where the artifact will be created (default: `build/test-artifact.bin`).
- `_SIGNATURE_BUCKET` — GCS bucket to upload signature (optional for local testing).
- `PUBLIC_KEY_PATH` — path to the public key for verification (optional).

Manual validation steps
1. Set gcloud project and authenticate using the staging service account:

```bash
gcloud auth activate-service-account --key-file=/path/to/staging-sa.json
gcloud config set project your-staging-project
```

2. Run the staging validation script (this will fetch the signing key from GSM if `_SIGNING_SECRET_NAME` is set):

```bash
export _SIGNING_SECRET_NAME=terraform-signing-key
export _ARTIFACT_PATH=build/test-artifact.bin
# optional: provide public key path for verification
./scripts/validation/staging_signing_validate.sh "$_ARTIFACT_PATH" "" "/path/to/public_key.pem"
```

3. If you want to run in Cloud Build, use the `ci/cloudbuild-signing.yaml` example and set substitutions in the build trigger.

Automated checks
- Confirm `${_ARTIFACT_PATH}.sig` exists and is uploaded to the signature bucket if configured.
- If verification is enabled, `openssl` should report the signature as valid.

Troubleshooting
- Permission denied when accessing GSM: ensure the service account has `roles/secretmanager.secretAccessor` and the secret exists.
- `gcloud` errors about quota projects: set `gcloud auth application-default set-quota-project PROJECT_ID` if using ADC.

Next steps
- Once staging validation passes, add Cloud Build trigger and require signature verification in deploy pipeline.
