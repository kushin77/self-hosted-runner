---
title: Security hardening for self-hosted runner (artifact verification, SBOM, SLSA)
---

Goal
----

Integrate artifact signature verification, SBOM generation/consumption and SLSA provenance checks into the runner update pipeline.

Tasks
-----
- [ ] Integrate `cosign` verification in `self-update/apply-update.sh` (replace placeholder).
- [ ] Add SBOM generation hook in build pipeline (Syft) and publish alongside artifacts.
- [ ] Verify SBOM and provenance during update (reject on mismatch).
- [ ] Add test coverage: unit tests for verification logic and e2e tests for update flow.
- [ ] Document key distribution and rotation for verification keys.

Progress
--------
- [x] Basic cosign verify-blob integration added to `self-update/apply-update.sh` with `COSIGN_KEY` and `COSIGN_KEYLESS` support (placeholder, uses `cosign verify-blob`).
- [x] Added test `tests/self-update-cosign-test.sh` that uses a fake `cosign` binary to validate behavior when `COSIGN_REQUIRED=1`.
- [x] Added SBOM validation hook (basic checks) and `SBOM_REQUIRED` toggle.

Next
----
- Replace `cosign verify-blob` placeholder with production commands and key handling (e.g., key distribution via Vault, key rotation doc).
- Add SBOM generation in CI (`syft`) and include in release artifacts. Validate SBOM metadata against expected provenance.

Acceptance
---------
- `apply-update.sh` verifies signatures and refuses unsigned or unverifiable artifacts.
- SBOM presence is enforced for any artifact updates.
- A documented key rotation/runbook exists in `docs/security/`.
