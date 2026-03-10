# Ephemeral Runner Cleanup

Purpose: ensure runners are ephemeral and auto-cleaned to avoid resource drift and orphaned compute costs.

Script: `scripts/cleanup/cleanup_ephemeral_runners.sh`

Usage:

```bash
./scripts/cleanup/cleanup_ephemeral_runners.sh my-project us-central1-a 24
```

Behavior:
- Deletes instances labeled `runner=ephemeral` older than the specified TTL.
- Idempotent and safe to run often (deletes only matching label and age).

Automation:
- Schedule this script with Cloud Scheduler + Cloud Function or an internal cron on your automation host.
- Ensure the service account used has `compute.instances.delete` and `compute.instances.list`.
