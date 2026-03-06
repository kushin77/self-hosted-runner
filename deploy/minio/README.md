# MinIO Helm chart (scaffold)

This chart is an initial scaffold for deploying MinIO as an S3-compatible object store.

Notes:
- Production deployments must use persistent volumes and provide TLS and credentials via Vault or Kubernetes secrets.
- This is a starting point for CI smoke tests and will be hardened in follow-up PRs.
