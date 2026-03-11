## EPIC-6: GCP Service Account Bootstrap (quick start)

This document explains how to bootstrap a GCP service account for EPIC-6 and map its key into the multi-layer secret system (GSM → Vault → KMS).

Steps:
1. Prepare the project and choose a service account name (default: `epic6-operator-sa`).
2. Run:

```
scripts/gcp/setup-gcp-service-account.sh --project nexusshield-prod --sa-name epic6-operator-sa --roles "roles/storage.objectAdmin,roles/iam.serviceAccountUser"
```

3. At runtime, fetch credentials:

```
source scripts/gcp/gcp-credentials.sh
gcloud auth activate-service-account --key-file "$GOOGLE_APPLICATION_CREDENTIALS"
```

Notes:
- The script is idempotent and safe to run repeatedly. Keys are stored in GSM and optionally mirrored in Vault (path: `secret/gcp/epic6`).
- Avoid committing service account keys into git; this flow stores keys in secure backends only.
