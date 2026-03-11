# Phase 4 Verification & Uptime Check Documentation

## Verification Job Scheduling

### Option 1: Systemd Timer (Recommended for Servers)

**Installation**:
```bash
sudo cp systemd/verify-rotation.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable verify-rotation.timer
sudo systemctl start verify-rotation.timer
```

**Status**:
```bash
sudo systemctl status verify-rotation.timer
sudo systemctl list-timers verify-rotation.timer
```

**Logs**:
```bash
sudo journalctl -u verify-rotation.service -f
```

### Option 2: User Crontab (Already Installed)

Schedule is `0 4 * * *` (04:00 UTC nightly).

**View**:
```bash
crontab -l | grep verify-rotation
```

## API-Based Uptime Checks

The `infra/scripts/create-uptime-checks-api.py` script creates uptime checks via the **Monitoring API** with `Authorization` headers.

**Installation**:
```bash
pip install -r infra/requirements-phase4.txt
```

**Usage** (requires GSM token):
```bash
export PROJECT=nexusshield-prod
python3 infra/scripts/create-uptime-checks-api.py
```

**Features**:
- Reads token from GSM: `uptime-check-token`
- Creates 3 checks (backend health, backend status, frontend root)
- Adds `Authorization: Bearer <token>` header
- Idempotent: skips existing checks
- Works around org policy by using API directly

**Replace gcloud checks**:
If you want to migrate from gcloud-created checks to API checks:
1. Note the existing check IDs: `gcloud monitoring uptime list-configs --project=nexusshield-prod --format='value(name)'`
2. Run the API script to create new ones
3. Delete old gcloud-created checks: `gcloud monitoring uptime delete <check-id>`
4. Keep the new API-created checks (they'll have Authorization headers)

## Slack Alerting

The wrapper script (`ops/internal_runner/run-verify-rotation.sh`) reads `slack-webhook-ops-alerts` from GSM and posts failures to Slack.

**Setup**:
1. Create or obtain your Slack incoming webhook URL
2. Store in GSM:
   ```bash
   echo "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" \
     | gcloud secrets create slack-webhook-ops-alerts \
     --data-file=-
   ```
3. The wrapper will automatically alert on failure

## Logs & Monitoring

**Verification logs**:
- Local: `ops/internal_runner/verify-rotation-YYYY-MM-DD.log`
- GCS: `gs://nexusshield-ops-logs/verify-rotation/`

**Secret rotation metric**:
- Metric: `secret_rotation_events_uptime-check-token`
- Alert policy (threshold): no new version in 24h
- (Requires notification channel IDs in Terraform to activate)

## Troubleshooting

**Verification script fails**:
```bash
# Run manually
./scripts/tests/verify-rotation.sh
```

**Rotation function not triggering**:
```bash
# Check scheduler job
gcloud scheduler jobs describe rotate-uptime-token-job --location=us-central1

# Test publish message
gcloud pubsub topics publish rotate-uptime-token-topic \
  --message='{"action":"rotate"}'
```

**Check rotation history**:
```bash
gcloud secrets versions list uptime-check-token --format='table(name, created, state)'
```

## Architecture

```
Cloud Scheduler (03:00 UTC, daily)
  └─> Pub/Sub: rotate-uptime-token-topic
       └─> Cloud Function: rotate-uptime-token (Python)
            └─> GSM: add new version
            └─> Cloud Run: update services with latest secret

Verification Automation (04:00 UTC, daily)
  └─> Systemd Timer or Cron
       └─> scripts/tests/verify-rotation.sh
            └─> Pub/Sub publish
            └─> GSM versions check
            └─> GCS log upload
            └─> Slack alert (on failure)
```

## Known Limitations

1. **External uptime checks blocked by org policy**: Checks report 401 Unauthorized (see ISSUE_2468)
   - Workaround: Use API script with Authorization header (internal traffic only for now)
2. **Compliance module pending**: Requires `cloud-audit` IAM group creation (see ISSUE_2469)

---
See `PHASE_4_COMPLETION_REPORT_FINAL.md` for full Phase 4 status.
