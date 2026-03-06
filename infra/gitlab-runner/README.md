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
