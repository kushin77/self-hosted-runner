Title: Internal runner job — Verify rotation

Schedule: `0 4 * * *` (nightly 04:00 UTC)

Command to run on internal runner:

```bash
cd /home/akushnir/self-hosted-runner
scripts/tests/verify-rotation.sh > /tmp/verify-rotation-$(date +%F).log 2>&1
# Upload logs to GCS
gsutil cp /tmp/verify-rotation-$(date +%F).log gs://nexusshield-ops-logs/verify-rotation/ || true
```

Notes:
- The script will publish a message to `rotate-uptime-token-topic` and verify a new GSM secret version is created and Cloud Run envs are updated.
- Job artifacts should be retained in `gs://nexusshield-ops-logs/verify-rotation/`.
- On failure, the job should post to `#ops-alerts` and create an incident.
