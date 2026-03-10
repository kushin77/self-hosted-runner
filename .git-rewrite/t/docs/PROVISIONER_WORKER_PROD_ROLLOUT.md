# Provisioner Worker: Production Rollout Guide

This document describes the recommended steps to deploy the `provisioner-worker`
service in a production environment as part of the managed-mode runner
provisioning flow. It assumes you have already tested the setup in staging and
have working AppRole credentials from Vault (see `docs/VAULT_PROD_SETUP.md`).

## 1. Build a Production Container Image

For reliability and security, build a minimal Node.js container image that
includes only the compiled worker code and its dependencies. Example (Dockerfile):

```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY services/provisioner-worker/package*.json ./
RUN npm ci --production
COPY services/provisioner-worker .

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app .
ENTRYPOINT ["node", "worker.js"]
```

Push the image to your internal registry (e.g. `registry.example.com/provisioner-worker:latest`).

## 2. Configure Secrets

1. Create a Vault policy granting `read` access to app role secrets and
   paths under `secret/data/provisioner/*`.
2. Generate an AppRole (`provisioner-worker-role`), capture `role_id` and
   `secret_id` in CI/CD or a secure secret store.
3. Ensure the managed-auth service also has its own AppRole and Vault policy.

Set the following environment variables on the worker container or host:

```sh
VAULT_ADDR=https://vault.example.com
VAULT_ROLE_ID=<role-id>
VAULT_SECRET_ID=<secret-id>   # mount via secret manager, not in plain env
USE_TERRAFORM_CLI=1
JOBSTORE_PERSIST=1           # can be 0 if using redis queue only
JOBSTORE_FILE=/var/lib/provisioner-worker/jobstore.json
PROVISIONER_REDIS_URL=redis://redis.example.com:6379
```

## 3. Select a Deployment Method

### Container-based (Kubernetes/Swarm)

Create a deployment manifest or compose file using the production image and
above environment variables.  Mount a persistent volume for `JOBSTORE_FILE` if
using file persistence.

Example Kubernetes snippet:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: provisioner-worker
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: worker
        image: registry.example.com/provisioner-worker:latest
        env:
        - name: USE_TERRAFORM_CLI
          value: "1"
        - name: VAULT_ADDR
          value: "https://vault.example.com"
        # Vault role/secret injected via secrets or CSI driver
        volumeMounts:
        - name: jobstore
          mountPath: /var/lib/provisioner-worker
      volumes:
      - name: jobstore
        persistentVolumeClaim:
          claimName: provisioner-worker-jobstore
``` 

### Systemd on VMs or Bare Metal

Use a unit file similar to
`services/provisioner-worker/deploy/provisioner-worker.service`, but with the
production image or code path.  Ensure the process runs as an unprivileged user
and that `/var/lib/provisioner-worker` is writable by that user.

## 4. Queue Configuration

Prefer Redis for cross-instance job queuing. Set
`PROVISIONER_REDIS_URL` accordingly. If Redis is not available, the file-backed
jobStore will work but requires care with concurrency (#139) and does not
scale past one instance.

## 5. CI & Integration Tests

Add a workflow that:

1. Spins up a throwaway Vault (or uses real Vault with test Role ID).
2. Starts Redis and the production image locally or in GitHub Actions.
3. Executes the `services/managed-auth/tests/provision_flow.sh` script with
   `SECRETS_BACKEND=vault` to ensure end-to-end provisioning.

## 6. Monitoring & Alerts

- Expose `/metrics` from each worker; scrape with Prometheus.
- Alert if `provisioner_worker_jobs_failed_total` increases unexpectedly.
- Track Vault access failures and Redis connectivity issues.

## 7. Rollout Plan

1. Deploy worker and managed-auth to a staging namespace (already done).
2. Smoke-test by enqueuing a job and verifying resource creation in
   infrastructure (e.g. `null_resource` or cloud API stub).
3. Scale up to two replicas and repeat tests, verifying idempotency and
   job-store consistency.
4. Cut over production traffic by updating the production GitHub Actions
   pipeline or manual deployment script to use the production image and
   Vault roles.
5. Monitor metrics and logs; rollback by stopping the service if serious
   issues arise.

## 8. Documentation

- Add a section in the main README linking to this guide.
- Update `docs/VAULT_PROD_SETUP.md` with any new paths used by the worker.

---

For questions or to report issues during rollout, refer to
[#140](https://github.com/kushin77/self-hosted-runner/issues/140).