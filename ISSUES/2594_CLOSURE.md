Issue #2594 — Canonical Secrets On‑Prem Deployment — Closure Record

Status: CLOSED (recorded in repo)

Closure summary:
- Deployed `canonical-secrets` to on‑prem host 192.168.168.42 (service running under systemd).
- Branch with deployment artifacts and verification: `canonical-secrets-impl-1773247600`.
- Repository artifact: `canonical_secrets_artifacts_1773253164.tar.gz` (SHA256 truncated: 878fd9a4...7719).
- Validation: integration smoke tests passed; post‑deploy validation reports available in the repo and on the runner under `/tmp`.
- Notes: No AWS/GitHub credentials were available on the runner; artifact uploaded to repo for immutability. To publish externally, an operator may run `scripts/ops/publish_artifact_and_close_issue.sh` after configuring their S3 bucket and providing a GitHub personal access token in their shell, or upload manually and paste the URL into the file.

Timestamps:
- Deployment completed: 2026-03-11
- Record created: 2026-03-11

Operator actions remaining (optional):
- Upload artifact to S3 and replace the "Repository artifact" line with the public URL.
- Use the `scripts/ops/publish_artifact_and_close_issue.sh` script to post and close the issue on GitHub.

Links:
- Branch: canonical-secrets-impl-1773247600
- Artifact (repo): canonical_secrets_artifacts_1773253164.tar.gz
- Deployment docs: see `DEPLOYMENT_ARTIFACTS_RECORD.md` and `ISSUE_CLOSURE_PREP.md`
