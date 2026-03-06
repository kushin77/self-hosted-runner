---
title: "782 - Convert Terraform apply to reusable workflow"
date: 2026-03-06
status: closed
labels:
  - ci
  - automation
assignees:
  - infra
---

Summary
-------

Created `.github/workflows/reusable/terraform-apply-callable.yml` and refactored `terraform-apply.yml` to call it.

Why
---

Improves reuse, centralizes checksum verification, and ensures consistent apply behavior across triggers.

Status
------
Closed — change committed and pushed to `main` on 2026-03-06.
