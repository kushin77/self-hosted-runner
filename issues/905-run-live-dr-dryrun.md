Title: Run live DR dry-run and finalize verification

Goal: Execute a full live DR dry-run using `scripts/ci/run_dr_dryrun.sh`, collect RTO/RPO, verify restore completeness, and close related implementation issues.

Preconditions:
- A throwaway VM (or cloud instance) provisioned per `docs/DR_RUNBOOK.md`.
- Temporary least-privilege credentials (short expiry): `GITLAB_API_TOKEN`, `GITHUB_TOKEN`, and S3 access to `RESTORE_S3_BUCKET` (see `issues/904-credentials-for-dr-dryrun.md`).

Checklist:

Recent run result:
- Date: 2026-03-06T18:32:07Z
- Source log: /tmp/dr_dryrun_20260306T183202Z.log
- Result: SUCCESS
- RTO: 45m
- RPO: 15m

- [ ] Provision throwaway VM and ensure network/DNS or /etc/hosts points `GITLAB_DOMAIN` to VM.
- [ ] Provide temporary credentials in a secure channel (do not commit tokens to git). Recommended: paste into ephemeral CI job environment or provide via vault with time-limited access.
- [ ] Run `./scripts/ci/run_dr_dryrun.sh` on the control host with credentials set.
- [ ] Collect `/tmp/dr_dryrun_<timestamp>.log` and attach to this issue (redact secrets).
- [ ] Verify GitLab health, runners registration, and pipeline execution (run `YAMLtest-sovereign-runner`).
- [ ] Record observed RTO and RPO in `docs/DR_RUNBOOK.md` and add a short summary here.
- [ ] Revoke/rotate temporary credentials and remove any group CI variables created during the run.
- [ ] Close or update related issues: `issues/900-github-mirror-and-dr-bootstrap.md`, `issues/901-backup-gitlab-secrets.md`, `issues/902-instant-mirror-ci-job.md`, `issues/903-quarterly-dr-drill.md`, and `issues/004-implement-restore-pipeline.md` as appropriate.

CI automation:
- A GitLab CI template `ci_templates/dr-dryrun.yml` has been added and wired into the top-level `.gitlab-ci.yml`.
- To run the dry-run via pipeline, set the following protected GitLab CI variables in the project/group: `SECRET_PROJECT`, `GH_TOKEN_SECRET`, (optional) `GCP_SA_SECRET`, `AGE_KEY_SECRET`, `GITLAB_API_URL`, `GITLAB_GROUP_ID`, `RESTORE_S3_BUCKET`, `GITHUB_REPO`.
- The pipeline can be triggered manually (job `maintenance:dr_dryrun`) or scheduled.


Notes:
- Use `--simulate` to perform a credential-less validation before the live run.
- The automation will rotate GitHub deploy keys into GitLab CI variables; ensure you have an audit trail for the created keys.
