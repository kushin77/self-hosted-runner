---
title: "781 - Enable branch protection and required status checks for main"
date: 2026-03-06
status: open
labels:
  - ops
  - security
  - policy
assignees:
  - repo-admins
---

Request
-------

Please enable branch protection on `main` with the following required status checks:

- `Workflow Sequencing Audit` (PR check)
- `Terraform Plan (consume Packer AMI)` or its reusable callable equivalent
- `Terraform Apply` (where applicable, for PR gating)
- `E2E validate` or `self-hosted-e2e` checks

Additional protections recommended:
- Require Draft issue reviews before merge (1-2 reviewers)
- Require signed commits
- Restrict who can push to `main` (administrators or release-bot)

Notes
-----
This must be configured by repository administrators via GitHub settings or organization policy. I cannot enable this automatically from the repository files.
