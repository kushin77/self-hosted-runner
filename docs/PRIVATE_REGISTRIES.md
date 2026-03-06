Private Registries & Artifact Stores
=================================

This document covers the recommended approach for hosting internal registries and artifact stores to support full sovereignty.

Choices
-------
- MinIO: S3-compatible object store for artifacts and Helm chart storage (lightweight).
- Nexus / Artifactory: full-featured artifact registries if you need npm/nuget/maven/pypi hosting with repository management.

Staging plan (current):
- Use `deploy/minio` chart as initial object store for artifacts and Helm charts.
- Configure CI to push build artifacts to `registry.internal` and store image tarballs/artifacts in MinIO.

Secrets and access
------------------
- Provide MinIO credentials via Kubernetes secrets or a Vault injector. Do NOT hardcode credentials in YAML.
- CI workflows should pull credentials from Vault or repository secrets and authenticate at runtime.

Publishing images/packages
-------------------------
- For container images, run a local registry (Harbor or registry:2) and configure CI to `docker login` using `ci/scripts/login-registry.sh`.
- For archives and Helm charts, use MinIO as the object store and store references in Helm repo indices.

Next steps
----------
- Deploy MinIO to staging via `.github/workflows/deploy-minio.yml` (manual dispatch).
- Add CI steps to publish images to the internal registry and artifact bundles to MinIO.
