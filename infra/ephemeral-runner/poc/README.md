POC: Golden Image → Ephemeral Runner

Overview

This POC verifies using the `golden-image` as the base for ephemeral CI runners.
It deploys a Kubernetes `Job` that pulls the repository and runs the smoke-fastpath
(lint + type checks) inside the pre-baked image.

Usage

1. Make the image available to your cluster:
   - Option A (preferred): Push `golden-image:latest` to a registry (GHCR/ACR/ECR) and update the image name in `runner-job.yaml`.
   - Option B (local): `kubectl create secret docker-registry` + `kubectl` load the tar into nodes (cluster-specific).

2. Apply the Job:

```bash
kubectl apply -f infra/ephemeral-runner/poc/runner-job.yaml
kubectl -n default logs -f job/golden-image-smoke-poc
```

3. Expected result: the Job completes and the logs show `ruff` and `mypy` output.

Notes

- The job clones the public `elevatediq-ai/ElevatedIQ-Mono-Repo` repo; if you need to clone private repos, mount a secret with credentials.
- This POC is intentionally simple: it demonstrates image suitability and startup speed.

Next steps (after validation)

- Replace job with `RunnerDeployment` CR from `actions-runner-controller` to register ephemeral runners with GitHub.
- Measure image cold-start time and registry pull size; optimize image if necessary.
- Automate pushing `golden-image` to GHCR in the `build-golden-image` workflow when CI artifacts pass.
