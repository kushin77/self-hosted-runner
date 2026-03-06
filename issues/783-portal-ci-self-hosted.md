---
title: "783 - Make Portal CI self-hosted and add sequencing guard"
date: 2026-03-06
status: closed
labels:
  - ci
  - infra
assignees:
  - infra
---

Summary
-------

Updated `portal-ci.yml` to run on self-hosted runners and added `concurrency` to serialize runs.

Why
---

Ensures portal CI runs on on-prem infrastructure (sovereign runners) and avoids overlapping runs that could conflict with deployments.

Status
------
Closed — change committed and pushed to `main` on 2026-03-06.
