# Governance Enforcement

This document describes scheduled checks and enforcement for repository governance policies:
- No GitHub Actions for releases
- No pull-request based releases
- Immutable audit trail for automatic removals
- Direct development and direct deployment only

Files added:
- `tools/governance-scan.sh` — script that scans tags and recent commits for disallowed actors and reports to the audit issue.

Recommended operational setup:
1. Create a Cloud Build trigger (cron) or Cloud Scheduler job to run `tools/governance-scan.sh` daily (or hourly for stricter monitoring).
2. Supply the build with a `GITHUB_TOKEN` stored in Secret Manager and pass it as `_GITHUB_TOKEN_SECRET` (or `GITHUB_TOKEN` env directly).
3. If a violation is detected, the script will post to the canonical audit issue (#2619) and create `governance/escalation` issues for human follow-up.

Cloud Build sample step (example):
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: 'bash'
  args:
  - -c
  - |
    set -euo pipefail
    GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="_GITHUB_TOKEN_SECRET" --project="$PROJECT_ID")
    export GITHUB_TOKEN
    chmod +x tools/governance-scan.sh
    ./tools/governance-scan.sh

Operational notes:
- The script is idempotent and safe to run repeatedly.
- It records findings to the audit issue and creates escalation issues for each detected violation.
- To disable scanning temporarily, set `DISABLE_GOVERNANCE_SCAN=1` in the build environment.

If you want, I can create the Cloud Build trigger on your behalf (requires cloud project permissions). Otherwise, create the trigger and I will validate the first run and post results to the audit issue.