# Store Slack Webhook in Vault (Operator Runbook)

This runbook explains the safe, auditable, operator steps to store an incoming Slack webhook in Vault (KV v2) at `secret/data/ci/webhooks` and how to validate Alertmanager -> Slack delivery.

Prerequisites
- A Vault operator account with a short-lived `VAULT_TOKEN`, or an AppRole `role_id` + `secret_id` that can write to the `secret/ci/webhooks` path.
- Network connectivity from your operator host to `VAULT_ADDR` and to `http://192.168.168.42:9093` (Alertmanager) if you intend to test via Alertmanager.

Security notes
- Never paste the webhook into GitHub, issues, or public logs.
- Use ephemeral tokens or AppRole secret IDs; revoke them after use.

Steps

1) Export Vault address and method

```bash
export VAULT_ADDR="https://vault.your.domain:8200"
# Option A: short-lived operator token
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# Option B: AppRole (preferred for automation)
# export VAULT_ROLE_ID="<role_id>"
# export VAULT_SECRET_ID="<secret_id>"  # or file /run/secrets/vault_secret_id
```

2) Verify connectivity (do not expose tokens if copying output)

```bash
vault status || (echo "Vault unreachable" && exit 2)
```

3) Store the webhook using the provided helper (recommended)

```bash
# Usage: scripts/vault_store_webhook.sh <SLACK_WEBHOOK_URL>
./scripts/vault_store_webhook.sh "https://hooks.slack.com/services/T000/BBB/XXXX"
```

What the helper does
- Writes the secret to KV v2 at `secret/data/ci/webhooks` with key `slack_webhook`.

4) Manual KV v2 command (alternative)

```bash
vault kv put secret/ci/webhooks slack_webhook="https://hooks.slack.com/services/T000/BBB/XXXX"
```

5) Verify the secret is present (operator only)

```bash
vault kv get -format=json secret/ci/webhooks
```

6) Validate Alerting

- Option A (Alertmanager v2 API): run the repository test script from the repo root

```bash
./scripts/automated_test_alert.sh
```

- Option B (direct Slack POST for troubleshooting)

```bash
TEST_SLACK_WEBHOOK="https://hooks.slack.com/services/T000/BBB/XXXX" ./scripts/automated_test_alert.sh
```

7) Close the loop
- If Slack receives the synthetic alert, comment `Verified — Slack alert received` on Issue #812 and close it.
- Revoke any ephemeral tokens used for this operation.

Troubleshooting
- `vault status` returns connection refused: confirm `VAULT_ADDR` and network routing.
- Alertmanager v2 rejects the alert: check `deploy/monitoring/alertmanager/config.yml` and ensure Alertmanager can reach Slack (or that `SLACK_WEBHOOK` is correctly injected into the container env).

References
- `scripts/vault_store_webhook.sh` — helper that writes to Vault
- `scripts/fetch_vault_secrets.sh` — runner helper that loads secrets into the environment
- `deploy/monitoring/alertmanager/config.yml` — Alertmanager receiver template

Contact
- Tag `@akushnir` on the issue if you need operator help or to schedule privileged runs.
