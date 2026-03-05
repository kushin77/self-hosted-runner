---
title: Implement runner self-update and healing
---

Summary
-------

Implement a safe, auditable self-update and healing system for the self-hosted runner.

Acceptance criteria
---------------
- A `check-updates.sh` script that determines whether an update is available.
- An `apply-update.sh` script that can apply updates (supports `--dry-run`).
- Documentation and example `systemd` units/timers to schedule updates.
- Smoke tests to validate scripts exist and basic control flow.

Implementation checklist
----------------------
- [x] Add `self-update/check-updates.sh` (placeholder logic)
- [x] Add `self-update/apply-update.sh` (simulated apply)
- [x] Add `self-update/version` token
- [x] Add `deploy/systemd/runner-self-update.{service,timer}` examples
- [x] Add `tests/self-update-test.sh` smoke test
- [x] Add `self-update/README.md` with instructions
- [x] Implement atomic apply + symlink swap and basic rollback (added)
- [x] Add `self-update/health-check.sh` and atomic smoke test (added)

Status
------

All planned placeholder components implemented. Security hardening (cosign, SBOM verification, provenance) is tracked separately and remains to be completed with production keys and CI integration.

QA / Runbook
-----------
1. Run `sh tests/self-update-test.sh` to validate basic scripts.
2. Replace placeholder verification with `cosign` verification and real artifact storage.
3. Create a PR with production-safe update steps and required rollback strategy.

Notes
-----
This is intentionally minimal and safe; it does not perform unverified binary swaps. The production implementation must include artifact signing verification, atomic replacement (e.g., symlink swap + health-check), and rollback.
