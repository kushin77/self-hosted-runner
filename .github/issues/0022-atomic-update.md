---
title: Implement atomic update and rollback for runner
---

Summary
-------

Implement an atomic update mechanism for the self-hosted runner that supports:
- staged extraction of artifact into a release directory
- atomic symlink swap to `current`
- health-check and automatic rollback on failure

Acceptance
---------
- Update uses releases directory and symlink swap.
- Health-check script is executed post-deploy and rollback occurs on failure.
- Tests cover the atomic swap (see `tests/self-update-atomic-test.sh`).

Implementation checklist
----------------------
- [x] Add releases directory layout and symlink management (implemented)
- [x] Add `self-update/health-check.sh` (implemented)
- [x] Add smoke test `tests/self-update-atomic-test.sh` (implemented)
- [ ] Integrate with real artifact store and signed artifacts
