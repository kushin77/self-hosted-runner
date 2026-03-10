Title: Grant Artifact Registry / GCR push permissions for CI/deployer

Description
- The deployment attempts to push Docker images to `gcr.io/<PROJECT>/portal-backend` but received `denied: Unauthenticated request`.

Required actions (urgent)
- Priority: **High** — needed to publish built images for deployment.
- Assignee: `platform-ops` (or `infra-team`)
- Steps:
  1. Ensure Artifact Registry repository exists (example):

     gcloud artifacts repositories describe portal-backend-repo --location=us-central1 --project=<PROJECT> || \
       gcloud artifacts repositories create portal-backend-repo --repository-format=docker --location=us-central1 --description="Portal backend repo" --project=<PROJECT>

  2. Grant the deployer SA permission:

     gcloud projects add-iam-policy-binding <PROJECT> --member="serviceAccount:nxs-portal-production@<PROJECT>.iam.gserviceaccount.com" --role="roles/artifactregistry.writer"

  3. Verify by building and pushing a test image:

     docker build -t us-central1-docker.pkg.dev/<PROJECT>/portal-backend-repo/portal:latest ./backend
     docker push us-central1-docker.pkg.dev/<PROJECT>/portal-backend-repo/portal:latest

Verification steps
- From an environment with the deployer SA active, run:
  - `docker build -t REGION-docker.pkg.dev/<PROJECT>/portal-backend/portal:latest ./backend`
  - `docker push REGION-docker.pkg.dev/<PROJECT>/portal-backend/portal:latest`
- Alternatively, run the repo's `scripts/direct-deploy-production.sh` after permission is granted.

Notes
- If you prefer the CI to push images, provide a short-lived signed service account key or configure Workload Identity for the runner.
- Contact: infra-team (cc:platform-ops)
