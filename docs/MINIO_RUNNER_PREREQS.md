# MinIO & Self-Hosted Runner Prerequisites

This document describes the minimum configuration and secrets required for self-hosted runners to use the in-repo MinIO artifact pattern and to perform GitOps bootstrapping (SealedSecrets / ExternalSecrets).

## Goals
- Allow workflows running on self-hosted runners to upload/download artifacts to an in-house MinIO bucket.
- Document runner-level tooling and required secrets for reproducible staging validation.

## Required GitHub Secrets (repository or org level)
- `MINIO_ENDPOINT` — e.g. `https://minio.internal.example.com`
- `MINIO_ACCESS_KEY`
- `MINIO_SECRET_KEY`
- `MINIO_BUCKET` — bucket name used for CI artifacts

> Note: For sensitive workflows you can store MinIO credentials in Vault and only expose short-lived credentials to runners via an AppRole + ExternalSecrets pattern.

## Runner prerequisites (staging/self-hosted)
- Network access from runner to `MINIO_ENDPOINT` on HTTPS (443) or configured port.
- `mc` (MinIO client) installed or `aws` CLI configured for S3-compatible access. The in-repo scripts use `mc` by default.
- `kubectl`, `helm`, `kustomize`, `terraform`, `pack`, and other CI tools as required by the workflow. Use the repository `ci/scripts/setup-*.sh` helpers to install predictable versions.
- Docker / container runtime present if building container images.

## Service account / least privilege guidance
- Create a dedicated MinIO user with scoped permissions limited to the CI bucket/prefix used by the repo.
- Rotate access keys regularly and prefer short-lived credentials (Vault) where possible.

## SealedSecrets and GitOps notes
- The SealedSecrets public key used to seal secrets must match the target cluster. Keep the public key in `deploy/gitops/bootstrap/sealed-secrets-publickey.pem` (or document location).
- Do NOT commit plaintext secrets. Use `ci/scripts/generate_sealed_secret.sh` to produce sealed secrets; store generated sealed secrets in MinIO or the Git repository only after review.

## Example usage (upload)

The repository contains `ci/scripts/upload_to_minio.sh` and `ci/scripts/download_from_minio.sh`. Example invocation in a workflow step:

```bash
./ci/scripts/upload_to_minio.sh --endpoint "$MINIO_ENDPOINT" --access-key "$MINIO_ACCESS_KEY" --secret-key "$MINIO_SECRET_KEY" --bucket "$MINIO_BUCKET" --file "kubeconform-report.json" --key "validate-manifests/${{ github.sha }}/kubeconform-report.json"
```

## Next steps for validation
- Provide staging runner(s) with the secrets above.
- Run the updated `validate-manifests.yml` workflow on the staging runner and verify artifacts land in the configured `MINIO_BUCKET`.
- After validation, proceed to replace remaining `actions/upload-artifact` / `download-artifact` usages per-workflow (create small PRs per workflow).
