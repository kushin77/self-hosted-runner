# Phase P4 — E2E Validation & Ops Runbook

Purpose: Provide step-by-step instructions for Ops to validate Phase P4 features in staging and to perform safe rollout to production.

Prerequisites
- Staging project with staging VPC and subnet configured.
- `STAGING_KUBECONFIG` secret available in GitHub Actions for CI-driven validation.
- `PUSHGATEWAY_URL` or Prometheus endpoint accessible for autoscaling tests.
- Service accounts with least-privileged rights for Terraform and Kubernetes applies.

Validation Steps

1) Terraform staging preview

```bash
cd terraform/environments/staging-tenant-a
terraform init
terraform plan -out=plan.out
```

Review produced plan for instance template metadata entries, firewall rules, and the KEDA helm release.

2) Deploy staging resources (approval required)

- Apply the plan or run `terraform apply plan.out` after approvals. Use a throwaway staging project if available.

3) Validate Vault Agent metadata-injection flow

- Boot an instance from the generated template and SSH in.
- Confirm files written by metadata injector:
  - `/etc/vault-agent/vault-agent.hcl`
  - `/etc/vault-agent/registry-creds.tpl`
  - `/etc/systemd/system/vault-agent.service` (if injected)
  - `/usr/local/bin/vault-renewal.sh`
- Start and inspect services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vault-agent.service || true
sudo systemctl enable --now vault-renewal.service || true
journalctl -u vault-agent -f
```

4) Validate runner startup and registry login

- Run the startup wrapper: `sudo /opt/runner/runner-startup.sh` (path depends on image).
- Confirm Docker login to the target registry and that the runner registers with GitHub.

5) Validate KEDA install and CRDs

```bash
kubectl --kubeconfig=/path/to/kubeconfig get crd scaledobjects.keda.sh
kubectl get deployment -n keda
```

6) Deploy Pushgateway and generate test metrics (staging)

```bash
kubectl apply -f deploy/autoscaling/test-harness/pushgateway-deployment.yaml -n runners
PUSHGATEWAY_URL=http://pushgateway.runners.svc:9091 ./deploy/autoscaling/test-harness/metric-generator.sh
```

7) Deploy sample ScaledObject and observe scaling behavior

```bash
kubectl apply -f deploy/autoscaling/sample/github-runner-deployment.yaml
kubectl apply -f deploy/autoscaling/sample/scaledobject.yaml
kubectl get pods -n runners --watch
```

8) GitOps policy validation

- On Draft issues that update `deploy/policies/**`, the workflow `validate-policies-and-keda.yml` will run client-side validation.
- After `STAGING_KUBECONFIG` is provided, run the `keda-smoke-test` workflow to perform server-side dry-run and optionally apply with approval.

Rollback and Cleanup
- Remove sample artifacts:

```bash
kubectl delete -f deploy/autoscaling/sample/scaledobject.yaml || true
kubectl delete -f deploy/autoscaling/sample/github-runner-deployment.yaml || true
kubectl delete -f deploy/autoscaling/test-harness/pushgateway-deployment.yaml || true
```

Operational Notes
- Do not store production secrets in instance metadata. Use Workload Identity or secure bootstrap flows.
- Rotate any staging service account kubeconfigs or tokens after testing.
- Confirm RBAC least-privilege principles for the CI service account before enabling server-side applies in CI.
