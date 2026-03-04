# provisioner-worker Terraform runner

This folder contains a small Terraform runner shim used by `provisioner-worker`.

Current state
- `lib/terraform_runner.js` is a non-destructive stub that simulates `apply` and `destroy` actions.

How to replace with real Terraform
1. Decide whether you want to call the Terraform CLI (`child_process.spawn`) or use a library.
2. Implement workspace lifecycle: `init`, `validate`, `plan -out`, `apply` and `destroy`.
3. Ensure idempotency by tracking applied plan IDs in `jobStore` and skipping duplicate work.
4. Use environment-scoped state backends (remote state like S3/GCS) for team usage.

Quick test (local):

```sh
node -e "const tr=require('./lib/terraform_runner'); tr.applyPlan({id:'test-1'}).then(r=>console.log(r))"
```
Provisioner Worker (scaffold)
=================================

This directory contains a scaffold for the provisioner worker which will dequeue provisioning jobs
and invoke Terraform / cloud APIs to create runners.

Local demo
----------
1. Start the in-process worker (no Redis required):

```bash
# from repo root
node services/provisioner-worker/index.js &
```

2. Enqueue a demo job (this uses the in-repo `services/provisioner` enqueue API):

```bash
node services/provisioner-worker/demo_enqueue.js
```

Notes
-----
- The worker supports a Redis-backed mode when `REDIS_URL` is set. Implement the Terraform/infrastructure calls
  in the worker loop where indicated.
- This scaffold is intentionally minimal; for production add idempotency, retries, observability, and secure credentials.
