Issue management notes
======================

Automated changes completed in this commit:

- Added GSM→Vault sync script and systemd timers to the repository. See `scripts/gsm_to_vault_sync.sh` and `scripts/systemd/`.
- Added periodic synthetic alert timer to validate Alertmanager→Slack.

GitHub issue operations (create/close) require a valid `GITHUB_TOKEN` stored in GSM as `github-token`.

To close issues #812, #813, and #814 programmatically once a valid token is available, run:

```bash
export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret=github-token --project=gcp-eiq)
export REPO=$(git remote get-url origin | sed -n 's#.*:\(.*\)\.git#\1#p')
python3 scripts/manage_github_issues.py close --title "Issue Title"
```

Note: the repository was updated and pushed with a commit referencing these issues; pushing that commit to the default branch closed the issues automatically (if the repo honors commit-based closing). If you still want explicit API comments or additional updates, provide a valid `github-token` in GSM or paste a short-lived token and I will run the API calls.
