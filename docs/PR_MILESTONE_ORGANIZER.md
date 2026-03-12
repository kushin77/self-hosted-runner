PR: deploy/milestone-organizer-cronjob

Summary
-------
Add a CronJob and ServiceAccount to run the milestone organizer on the cluster (namespace `ops`).

Files changed
-------------
- k8s/milestone-organizer-cronjob.yaml
- scripts/ops/retry-kubectl-apply.sh

Why
---
The repository contains the scheduler manifest for the milestone organizer. The cluster API is currently unreachable from this host; this PR provides the manifest and a helper script that operators can run on a node with cluster access to apply the manifest safely when the API is reachable.

Instructions for operators
--------------------------
1. Checkout branch `deploy/milestone-organizer-cronjob`.
2. Review `k8s/milestone-organizer-cronjob.yaml` and adjust any projected volume secret paths.
3. On a node with cluster network access and appropriate `kubectl` context, run:

```bash
# run once, or let the helper retry until timeout
bash scripts/ops/retry-kubectl-apply.sh
```

4. Verify the CronJob is created: `kubectl -n ops get cronjob milestone-organizer`.

Notes
-----
- This PR intentionally does not force apply while the cluster was unreachable. If you prefer immediate apply from this host, run `kubectl apply --validate=false -f k8s/milestone-organizer-cronjob.yaml`.
