Title: Security hardening: Self-update (cosign, SBOM, atomic deploy, health-check)

Description
-----------
This draft PR implements the self-update security hardening work: artifact signature verification (cosign), SBOM validation, atomic release extraction and symlink swap, health-check and rollback, and accompanying tests and documentation.

Changes include (high level):
- `self-update/` — `check-updates.sh`, `apply-update.sh`, `health-check.sh`, `version`, `README.md`, `update-checker.sh`.
- `tests/` — smoke tests: `self-update-test.sh`, `self-update-atomic-test.sh`, `self-update-cosign-test.sh`, `self-update-sbom-test.sh`.
- CI workflow: `.github/workflows/generate-sbom.yml` to create SBOMs with `syft`.
- Issues: `.github/issues/0020-self-update-implementation.md`, `0021-security-hardening.md`, `0022-atomic-update.md`, `0023-sbom-integration.md`.
- Docs: `docs/security/SBOM_INTEGRATION.md`, other supporting docs.

Linked issues
- #20 — Implement runner self-update (implementation tracking)
- #21 — Security hardening (cosign + SBOM)
- #22 — Atomic update and rollback
- #23 — SBOM integration

Testing
-------
All local smoke tests under `tests/` passed in the workspace. CI should run the `generate-sbom` workflow to produce SBOM artifacts for release testing.

Notes / Next steps
- Replace placeholder cosign commands with production key handling (Vault integration, key rotation).
- Integrate SBOM publishing with release pipeline and enforce `SBOM_REQUIRED=1` in production release jobs.
- Add PR checks to run the smoke tests.
