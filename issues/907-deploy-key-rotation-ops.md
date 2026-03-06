Title: Deploy Key Rotation & Storage (Ops Finalization)

Goal: Rotate the GitHub mirror deploy key, upload the public key to GitHub, and store the private key as a protected GitLab CI variable.

Status: Ready for Ops

Preconditions:
- `gitlab-api-token` is stored in GSM (see `issues/906-gitlabtoken-provisioning-and-schedule.md`).
- `github-token` exists in GSM (confirmed present).

Checklist:

- [ ] Confirm `gitlab-api-token` is in GSM:
  ```bash
  gcloud secrets versions access latest --secret=gitlab-api-token --project=gcp-eiq | wc -c
  ```
- [ ] Run the idempotent deploy key rotation script:
  ```bash
  export SECRET_PROJECT=gcp-eiq
  export GITHUB_REPO="akushnir/self-hosted-runner"  # or your GitHub backup repo
  export GITLAB_API_URL="https://gitlab.com/api/v4"
  export GROUP_ID="1"  # or your target GitLab GROUP_ID or PROJECT_ID
  ./scripts/ci/rotate_github_deploy_key.sh
  ```
- [ ] Verify public key was uploaded to GitHub (GitHub repo → Settings → Deploy keys → check for "ci-mirror-<timestamp>").
- [ ] Verify private key was stored as a protected CI variable in GitLab (Project → Settings → CI/CD → Variables → `GITHUB_MIRROR_SSH_KEY` should be present, protected, and masked).
- [ ] Revoke the old deploy key if needed (optional; the script does this if `REMOVE_OLD_KEY_ID` is provided).
- [ ] Close this issue once verification is complete.

Reference:
- Ops Finalization Runbook: `docs/OPS_FINALIZATION_RUNBOOK.md` (Step 4)
- Rotation script: `scripts/ci/rotate_github_deploy_key.sh`
- Generated keypair note: `ops/rotation/rotate_key_20260306T183538.md`

Note: The script is idempotent and checks for existing keys before creating new ones. Safe to re-run.
