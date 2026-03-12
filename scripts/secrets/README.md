Rotate credentials helper

Purpose:
- `rotate-credentials.sh` is a safe, idempotent helper to stage credential rotations and store new secrets into Google Secret Manager (GSM).

Quick start (dry-run):

```bash
GSM_PROJECT=my-gcp-project ./scripts/secrets/rotate-credentials.sh status
GSM_PROJECT=my-gcp-project ./scripts/secrets/rotate-credentials.sh github
```

To apply changes (destructive):

```bash
GSM_PROJECT=my-gcp-project GITHUB_PAT="<new-pat>" ./scripts/secrets/rotate-credentials.sh github --apply
```

Requirements:
- `gcloud` CLI authenticated and access to the target project
- `jq` and `curl` (for Vault integration)

Security:
- Script is dry-run by default; it will not write secrets to GSM unless `--apply` is provided.
- Prefer running this from a secure admin workstation or CI job with short-lived credentials.
