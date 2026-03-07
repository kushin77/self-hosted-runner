# Remediation: Replace GCP Service Account Key

When the repository's `GCP_SERVICE_ACCOUNT_KEY` is invalid or truncated, follow these steps.

1. Export the full service account JSON from Google Cloud IAM (ensure `type: "service_account"` and `project_id` are present).
2. Validate locally:

```bash
jq . key.json
jq -e '.type == "service_account" and (.project_id|type == "string" and .project_id != "")' key.json
```

3. Upload securely using the included helper (runs locally in an operator machine):

```bash
cat key.json | ./scripts/ingest-gcp-key-safe.sh --repo kushin77/self-hosted-runner --secret-name GCP_SERVICE_ACCOUNT_KEY
```

4. Re-run verification workflow: `Verify Secrets Configuration` (see Actions → Workflows) or run:

```bash
gh workflow run verify-secrets-and-diagnose.yml --repo kushin77/self-hosted-runner --ref main
```

5. After the verify workflow reports success, re-run DR smoke tests.

Notes:
- This script requires `jq` and `gh` CLI authenticated with sufficient permissions.
- The script never stores the key on disk permanently.
