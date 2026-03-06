# Task: Deploy MinIO as internal artifact store (staging)

- Related Epic: SOV-005
- Status: in-progress
- Owner: Platform

## Objective
Deploy MinIO to staging cluster and add CI steps to publish artifacts and Helm charts to the internal store.

## Checklist
- [x] Add `deploy/minio/values.sov-staging.yaml`.
- [x] Add `docs/PRIVATE_REGISTRIES.md`.
- [x] Add `.github/workflows/deploy-minio.yml` to deploy manually to staging.
- [ ] Add CI steps to publish artifacts to MinIO (next).
