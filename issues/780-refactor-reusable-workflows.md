---
title: "780 - Refactor workflows to use reusable `workflow_call` patterns"
date: 2026-03-06
status: closed
labels:
  - ci
  - automation
  - enhancement
assignees:
  - infra
---

Summary
-------

Created a reusable callable workflow for Terraform plan and updated `terraform-plan-ami.yml` to invoke it.

Details
-------
- Added `.github/workflows/reusable/terraform-plan-callable.yml` (callable via `workflow_call`).
- Updated `terraform-plan-ami.yml` to call the reusable workflow with inputs `ami-tfvars` and `terraform-plan` as object names.

Next steps
----------
- Convert other plan/apply/deploy flows to `workflow_call` for stronger reuse and clearer sequencing.
- Define a standard inputs/outputs convention for reusable workflows (artifacts, checksums, env mappings).

Status
------
Partially complete: Terraform plan extracted and wired. Remaining conversions tracked as follow-up work.
