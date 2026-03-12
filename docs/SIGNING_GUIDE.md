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

# Sign an artifact (detached signature)
openssl pkeyutl -inkey signing_key.pem -sign -in artifact.bin -out artifact.bin.sig

# Verify
openssl pkeyutl -verify -pubin -inkey signing_key.pub -in artifact.bin -sigfile artifact.bin.sig
```

Integration notes
- Cloud Build: add a build step to fetch secret from GSM and execute the sign script. Ensure the build service account has only `roles/secretmanager.secretAccessor` and `roles/storage.objectCreator` as required.
- Rotation: when rotating keys, publish the new public key and maintain a transition window.

Files in this PR
- `scripts/signing/sign_artifact.sh` — simple wrapper to sign using `openssl` or `ssh-keygen`.
