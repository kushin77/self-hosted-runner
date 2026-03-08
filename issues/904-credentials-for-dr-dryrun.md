Title: Credentials and access required for autonomous DR dry-run

Goal: List minimal credentials and steps required to safely run the automated DR dry-run (`scripts/ci/run_dr_dryrun.sh`) so operators can create/provide temporary tokens.

Required items (minimal, least-privilege):

- `GITLAB_API_TOKEN` — Personal Access Token (or project access token) with `api` scope sufficient to create group/project CI variables and pipeline schedules.
- `GITLAB_API_URL` — Base URL for the GitLab instance (e.g. `https://gitlab.internal.elevatediq.com`).
- `GITLAB_GROUP_ID` — Numeric group ID (or `GITLAB_PROJECT_ID` where you want variables set).
- `GITHUB_TOKEN` — GitHub Personal Access Token (PAT) with `repo` scope and `admin:public_key` (or `repo` + `admin:repo_hook`) to add deploy keys.
- `GITHUB_REPO` — Mirror target `owner/repo` for push mirror.
- `RESTORE_S3_BUCKET` — S3 URL (e.g. `s3://my-backups`) with a lifecycle and access control. The DR job needs read access to the backup objects.
- Optional: `AGE_KEY_FILE_PATH` — content of `age` private key used to decrypt backups stored in S3 (or store the private key content as `AGE_KEY_FILE` group variable).

How to create these safely (recommended):

1. GitLab PAT:
   - In GitLab UI, create a Personal Access Token with `api` scope and short expiry (e.g., 1 day) for the dry-run.
   - Or create a Project Access Token scoped to the restore project with `api` scope.

2. GitHub PAT:
   - Create a PAT in the GitHub UI with `repo` and `admin:public_key` scopes. Add expiry and restrict to a least-privilege account.

3. S3 credentials / IAM:
   - Create an IAM user/role with a policy restricting access to the `RESTORE_S3_BUCKET` prefix. Example minimal policy (replace bucket and prefix):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::my-backups",
        "arn:aws:s3:::my-backups/*"
      ]
    }
  ]
}
```

4. `age` key (optional):
   - Generate with: `age-keygen -o key.txt` and provide the private key content as the `AGE_KEY_FILE` protected variable or set `AGE_KEY_FILE_PATH` pointing to a local file when running `run_dr_dryrun.sh`.

Security notes:
- Use short-lived tokens and rotate/delete after the dry-run.
- Prefer creating ephemeral credentials that expire automatically.
- Never paste unencrypted long-lived secrets into PRs or issues. Use ephemeral paste or out-of-band secure channel for sharing with the runner.

How to run locally (example):

```bash
export GITLAB_API_URL="https://gitlab.example.com"
export GITLAB_API_TOKEN="<TEMP_TOKEN>"
export GITLAB_GROUP_ID="12345"
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
export GITHUB_REPO="org/repo"
export RESTORE_S3_BUCKET="s3://my-backups"
# optional: export AGE_KEY_FILE_PATH="/path/to/age.key"

chmod +x scripts/ci/run_dr_dryrun.sh
./scripts/ci/run_dr_dryrun.sh
```

If you prefer, provide the credential block to the automation temporarily and I will run the dry-run and then clean up the credentials (removing group variables and rotate keys). See `scripts/ci/bootstrap_automation.sh` for the automation flow.
