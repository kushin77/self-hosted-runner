Title: Grant Artifact Registry / GCR push permissions for CI/deployer

Description
- The deployment attempts to push Docker images to `gcr.io/<PROJECT>/portal-backend` but received `denied: Unauthenticated request`.

Required actions
- Grant the deployer SA (or the provided CI account) the following roles on the artifact registry or GCR project:
  - `roles/artifactregistry.writer` (preferred for Artifact Registry)
  - or `roles/storage.objectAdmin` for legacy GCR buckets if still used
- If using Artifact Registry, ensure repository `portal-backend` exists and the SA has `artifactregistry.repositories.uploadArtifacts` permission.

Verification steps
- From an environment with the deployer SA active, run:
  - `docker build -t REGION-docker.pkg.dev/<PROJECT>/portal-backend/portal:latest ./backend`
  - `docker push REGION-docker.pkg.dev/<PROJECT>/portal-backend/portal:latest`
- Alternatively, run the repo's `scripts/direct-deploy-production.sh` after permission is granted.

Notes
- If you prefer the CI to push images, provide a short-lived signed service account key or configure Workload Identity for the runner.
- Contact: infra-team (cc:platform-ops)
