Triage summary — March 12, 2026

Actions taken:

- Created PR #2702: `chore(ops): add quick ops scripts for Cloud Build log access and SBOM/trivy runs` — adds:
  - `scripts/ops/grant-cloudbuild-log-access.sh`
  - `scripts/ops/run-sbom-and-trivy-on-approved-host.sh`
  - `docs/OPS_QUICK_COMMANDS.md`

- Created PR `ops/ci-log-upload` (this PR) adding:
  - `scripts/ops/upload-cloudbuild-logs.sh` (helper to copy Cloud Build logs by build id)
  - `cloudbuild/upload-logs-step.txt` (example Cloud Build post-step template)
  - `docs/TRIAGE_SUMMARY_2026-03-12.md` (this file)

Linked issues updated:
- #2678 — added `needs-ops`, assigned, commented with PR link (SBOM/Trivy script)
- #2679 — added `needs-ops`, assigned, commented with PR link
- #2684 — added `needs-ops`, assigned, commented with remediation commands and PR link

Next recommended steps (ops):
1. Provide the Cloud Build logs bucket name (e.g., `projects/_/logs/your-cloudbuild-logs`) so I can update the scripts and PR with the exact bucket.
2. Grant `roles/storage.objectViewer` (objectViewer) on the logs bucket to `deployer-run@nexusshield-prod.iam.gserviceaccount.com` (bucket-level least-privilege) or run the bucket-level `gsutil iam ch` command in PR #2702.
3. Merge PRs (2702 + this PR) once reviewed; then run the SBOM/Trivy script on the approved host and run the upload helper for the active build.

If you want, I can also add an automated Cloud Build job to run the upload step when builds complete (requires the bucket to be specified and IAM granted).