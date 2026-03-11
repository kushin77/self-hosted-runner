# Chaos Tests Cron Scheduling

This document shows how to schedule the chaos test orchestrator using `cron` on a hardened runner. The design follows immutable, ephemeral, idempotent and no-ops principles.

Example crontab (runs daily at 03:00 UTC):

```cron
0 3 * * * /bin/bash /opt/runner/repo/scripts/testing/run-all-chaos-tests.sh >> /var/log/chaos/orchestrator-$(date +\%F).log 2>&1
```

Best practices
--------------
- Run on a dedicated, hardened runner with limited outbound network.
- Use short-lived credentials fetched at runtime (GSM → Vault → KMS).
- Ensure `run-all-chaos-tests.sh` is idempotent and writes append-only JSONL logs.
- Rotate logs to immutable storage daily using `scripts/ops/upload_jsonl_to_s3.sh`.

Verification
------------
- Verify exit codes and audit JSONL outputs.
- Configure alerting on test failures and anomalous results.
