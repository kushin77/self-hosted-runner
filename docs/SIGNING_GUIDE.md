Terraform & Artifact Signing Guide

Location: `docs/SIGNING_GUIDE.md`

Overview
--------
This document describes the recommended approach for signing Terraform artifacts and release artifacts using Ed25519 keys managed securely in Google Secret Manager (GSM) or Vault. It is the tracked version of the scaffold (the `terraform/` folder may be git-ignored in this repo).

Key points
- Use Ed25519 keys for compact, secure signatures.
- Keep private keys in GSM/Vault; grant only a single CI/service account access to read the secret for signing.
- Perform signing in a trusted runner (Cloud Build, Buildkite, or self-hosted runner). Do not sign locally for production releases.
- Publish public keys to an allowlist used by deploy pipelines.

Commands (local testing only)
```bash
# Generate Ed25519 private key (PEM) with OpenSSL
openssl genpkey -algorithm Ed25519 -out signing_key.pem
openssl pkey -in signing_key.pem -pubout -out signing_key.pub

# Sign an artifact (detached signature) — preferred: `ssh-keygen`
# Using OpenSSH `ssh-keygen -Y sign` (recommended for Ed25519 keys):
ssh-keygen -Y sign -f signing_key.pem -n artifact < artifact.bin > artifact.bin.sig

# Verify with ssh-keygen:
ssh-keygen -y -f signing_key.pem > signing_key.pub
ssh-keygen -Y verify -f signing_key.pub -s artifact.bin.sig -n artifact < artifact.bin

# Fallback (OpenSSL) — note: some OpenSSL builds do not support Ed25519 signing:
openssl pkeyutl -inkey signing_key.pem -sign -in artifact.bin -out artifact.bin.sig

# OpenSSL verify (fallback)
openssl pkeyutl -verify -pubin -inkey signing_key.pub -in artifact.bin -sigfile artifact.bin.sig
```

Integration notes
- Cloud Build: add a build step to fetch secret from GSM and execute the sign script. Ensure the build service account has only `roles/secretmanager.secretAccessor` and `roles/storage.objectCreator` as required.
- Rotation: when rotating keys, publish the new public key and maintain a transition window.

Files in this PR
- `scripts/signing/sign_artifact.sh` — simple wrapper to sign using `openssl` or `ssh-keygen`.
Files in this PR
- `scripts/signing/sign_artifact.sh` — simple wrapper to sign using `openssl` or `ssh-keygen`.

Cloud Build example
-------------------
This example shows how to fetch a private key from GSM, run the signing script, and upload the signature to a GCS bucket. Do not store private keys in source control.

```yaml
# cloudbuild.yaml (example)
steps:
	- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
		id: 'fetch-signing-key'
		entrypoint: 'bash'
		args:
			- '-c'
			- |
				set -e
				gcloud secrets versions access latest --secret="${_SIGNING_SECRET_NAME}" > signing_key.pem
				chmod 600 signing_key.pem

	- name: 'gcr.io/cloud-builders/docker'
		id: 'run-sign'
		entrypoint: 'bash'
		args:
			- '-c'
			- |
				chmod +x scripts/signing/sign_artifact.sh
				./scripts/signing/sign_artifact.sh signing_key.pem "${_ARTIFACT_PATH}"

	- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
		id: 'upload-sig'
		entrypoint: 'bash'
		args:
			- '-c'
			- |
				gsutil cp "${_ARTIFACT_PATH}.sig" gs://${_SIGNATURE_BUCKET}/

substitutions:
	_SIGNING_SECRET_NAME: 'terraform-signing-key'
	_ARTIFACT_PATH: 'build/output/terraform-plan.zip'
	_SIGNATURE_BUCKET: 'my-signatures-bucket'

options:
	machineType: 'E2_HIGHCPU_8'

secrets:
	- kmsKeyName: '' # optional: encrypt secret using KMS

Security notes
- Give the Cloud Build service account only `roles/secretmanager.secretAccessor` and `roles/storage.objectCreator` for the specific resources.
- Use VPC-SC or Private Pools for sensitive signing steps where available.
