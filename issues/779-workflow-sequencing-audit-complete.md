---
title: "779 - Workflow sequencing audit and hardening — COMPLETE"
date: 2026-03-06
status: closed
labels:
  - automation
  - ci
  - security
  - infra
assignees:
  - ops
  - infra
---

Summary
-------

Implemented end-to-end workflow sequencing, artifact integrity, and runner sovereignty across the repository.

What I changed
- Added `.github/scripts/check_workflow_sequencing.py` — repo audit for workflow sequencing protections.
- Added `workflow-audit.yml` (PR-triggered) to run the audit against workflow/script Draft issues.
- Exempted `workflow-audit.yml` from auditing to avoid recursion.
- Added conservative `workflow_run` / job `if:` guards and `concurrency:` groups across workflows.
- Replaced usages of `runs-on: ubuntu-latest` with `[self-hosted, linux]` or `[self-hosted, linux, self-hosted-heavy]`.
- Added SHA256 plan checksum creation/upload in the plan workflow and checksum verification in the apply workflow.
- Hardened `scripts/minio/upload.sh` and `scripts/minio/download.sh` with exponential-backoff retries and strict exit codes.

Why
- Ensure downstream workflows do not run if upstream jobs fail.
- Ensure artifact integrity for Terraform plans to prevent blind or corrupted applies.
- Enforce on-prem sovereignty by running entirely on self-hosted runners.
- Make CI/CD resilient and fully automated (hands-off) while preserving manual dispatch when necessary.

Verification
- Ran the audit script locally: all workflows pass (report: `workflow-audit-report.txt`).
- Changes committed to `main` (see recent commits).

Follow-ups (optional)
- Add branch protection rules to enforce required status checks for PR merges.
- Convert common sequences to reusable `workflow_call` flows for clearer explicit sequencing.
- Add artifact checksums for additional artifact types (AMI tfvars, portal artifacts).

Resolution
- Status: closed — work completed and verified on 2026-03-06.
