# GitLab Runner (Kubernetes) — Deployment Guide

This folder contains artifacts and helpers to deploy a sovereign, ephemeral
GitLab Runner using the official Helm chart. Follow these steps to deploy
in a secure, idempotent, hands-off manner.

Prerequisites
-------------
- `kubectl` configured with a reachable context
- `helm` installed
- `kubeseal` (optional) for SealedSecrets workflow
- A registration token (one-time) for GitLab Runner registration

Recommended flow (secure, non-committing)
----------------------------------------
1. Generate a SealedSecret (preferred):

```bash
# preferred: create a sealedsecret using the helper and kubeseal
export REG_TOKEN="<REG_TOKEN>"
./scripts/ci/create_sealedsecret_from_token.sh "$REG_TOKEN" gitlab-runner
# If kubeseal is present: infra/gitlab-runner/sealedsecret.generated.yaml
# Otherwise: infra/gitlab-runner/secret.generated.yaml
```

2. Apply the secret to the cluster (apply the SealedSecret on the controller cluster):

```bash
kubectl apply -f infra/gitlab-runner/sealedsecret.generated.yaml
# OR for plain secret (test-only):
kubectl apply -f infra/gitlab-runner/secret.generated.yaml
```

3. Run the hands-off deploy script (idempotent):

```bash
export KUBECONFIG=~/.kube/config
./scripts/ci/hands_off_runner_deploy.sh
```

4. Verify pods and logs:

```bash
kubectl -n gitlab-runner get pods
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=200
```

5. Trigger the pipeline and validate the `YAMLtest-sovereign-runner` job.

Notes
-----
- Do NOT commit real tokens into Git. Use SealedSecrets or ExternalSecrets.
- If cluster is unreachable, consider provisioning a local Kind/k3d cluster for testing.

GCP Secret Manager (GSM) CI flow
--------------------------------
For fully hands-off deployments that avoid storing kubeconfigs or tokens in GitLab UI directly, you can store the required secrets in Google Cloud Secret Manager and let a protected CI job fetch them at runtime.

Recommended CI variables (protected, masked) in GitLab when using GSM:
- `GCP_PROJECT` — GCP project id
- `GCP_SA_KEY` — base64-encoded service account JSON key (least privilege; only Secret Manager access)
- `KUBECONFIG_SECRET_NAME` — secret resource name in GSM that contains the base64-encoded kubeconfig
- `REGTOKEN_SECRET_NAME` — secret resource name in GSM that contains the runner registration token

The repository includes a helper `scripts/ci/gcp_fetch_secrets.sh` used by a dedicated CI job `deploy:sovereign-runner-gsm`. The job authenticates to GCP using the provided service account key, retrieves the secrets from GSM, and then triggers the normal SealedSecret + Helm install workflow without exposing secrets in logs or Git.

If your environment supports Workload Identity or a CI-integrated GCP authentication mechanism, prefer that over storing long-lived keys in CI variables.

Local test cluster (KinD)
-------------------------
If you cannot reach the production cluster from this host, you can provision a local KinD cluster for smoke-testing. The repository contains a helper script:

```bash
./scripts/ci/provision_kind_cluster.sh gitlab-runner-test
```

Prerequisites: `docker` and `kind` installed. If `kubeseal` is required for SealedSecrets creation, use the helper below to download the client into `infra/tools`:

```bash
./scripts/ci/install_kubeseal_helper.sh 0.20.0
export PATH="$PWD/infra/tools:$PATH"
```

Once the local cluster exists, apply the generated secret (see `scripts/ci/create_sealedsecret_from_token.sh`) and run the hands-off deploy:

```bash
kubectl apply -f infra/gitlab-runner/sealedsecret.generated.yaml
./scripts/ci/hands_off_runner_deploy.sh
```

This creates an isolated test environment that mimics the production deployment in an ephemeral, immutable manner.
