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
