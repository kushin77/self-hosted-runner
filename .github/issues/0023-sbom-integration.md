---
title: SBOM generation and verification integration
---

Summary
-------

Generate SBOMs for release artifacts during CI and verify SBOM presence during self-update. Reject updates that lack valid SBOMs when `SBOM_REQUIRED=1`.

Acceptance criteria
-------------------
- A CI workflow generates SBOMs (see `.github/workflows/generate-sbom.yml`).
- `apply-update.sh` accepts `SBOM_URL` and validates basic SBOM content; setting `SBOM_REQUIRED=1` causes the update to fail if SBOM is missing or invalid.
- Local smoke test `tests/self-update-sbom-test.sh` verifies SBOM enforcement.

Implementation checklist
----------------------
- [x] Add CI workflow to generate SBOM using `syft`.
- [x] Add `apply-update.sh` support for `SBOM_URL` and `SBOM_REQUIRED` (basic validation).
- [x] Add local smoke test `tests/self-update-sbom-test.sh`.
- [ ] Integrate SBOM publish step into release pipeline and make SBOM artifact available alongside signed artifacts.
- [ ] Add SBOM provenance/SLSA validation step (future).
