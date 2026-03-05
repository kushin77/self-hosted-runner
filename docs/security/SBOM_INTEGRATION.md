SBOM Integration
================

This document outlines SBOM generation and verification guidance for the runner release process.

1. Generate SBOMs during CI using `syft`.
2. Publish SBOM artifacts alongside signed release artifacts.
3. During update, fetch the SBOM and validate basic structure. Enforce with `SBOM_REQUIRED=1`.
4. For production, validate SBOM contents against expected signatures/provenance and include SLSA checks.

See `.github/workflows/generate-sbom.yml` for an example workflow.
