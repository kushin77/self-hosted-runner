Pin Docker Base Images
======================

This folder contains `pin-base-images.sh`, a helper to replace Dockerfile base image tags
with the canonical image digest (image@sha256:...). This makes builds reproducible and
safer for supply-chain audits.

Prereqs:
- Docker CLI installed and logged in (network access required)

Example:

```bash
./scripts/pin-base-images.sh backend/Dockerfile.prod frontend/Dockerfile
git add backend/Dockerfile.prod frontend/Dockerfile
git commit -m "chore: pin Docker base images to digests"
```

Note: run this from the repo root. Review diffs before committing.
