# Google Secret Manager (GSM) Example

This folder contains guidance for using Google Secret Manager (GSM) alongside CI:

- Store non-rotating or environment configuration secrets in GSM.
- Use workload identity or short-lived service account keys to grant CI access.

Example approaches:

- Use GitHub OIDC to exchange for a short-lived GCP service account token (Workload Identity Federation).
- Or store service account keys in a secure internal system and inject them on self-hosted runners only.

See other docs in the repo for GSM architecture examples.
