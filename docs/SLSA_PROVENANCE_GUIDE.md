# SLSA Provenance Guide (scaffold)

This document describes the scaffolded provenance generation and optional attestation steps added to the repository.

## Overview

We generate simple SLSA-like provenance JSON documents for each image in the air-gap manifest and optionally attest them using `cosign attest`.

The purpose is to provide a minimal supply-chain provenance artifact that can be stored alongside SBOMs and image signatures.

## Scripts

- `scripts/supplychain/generate_provenance.sh` — reads `deploy/airgap/manifest.yml`, optionally finds an SBOM per-image in `build/sboms/`, and writes a provenance JSON into `build/provenance/`.
- The script can optionally call `cosign attest` to attach attestation to an image if a cosign key is provided. In CI, `COSIGN_KEY` is expected to be a base64-encoded private key secret. The CI workflow will write the key to a temp file and pass it to `cosign`.

## CI Workflow

- `.github/workflows/ci-provenance.yml` runs on release creation and manual dispatch.
- Steps:
  - Generate manifest
  - Ensure SBOMs are present or instruct to run `ci-supply-chain` first
  - Install `cosign` in the runner
  - Run `scripts/supplychain/generate_provenance.sh` to create provenance and (optionally) attest using cosign
  - Upload provenance artifacts as workflow artifacts

## Next Steps

- Replace simple provenance JSON with full in-toto/SLSA v1.0 predicate production (e.g., using build systems that produce SLSA provenance or `in-toto` tooling).
- Publish provenance and SBOMs to secure storage alongside release assets.
- Add verification gates in release pipelines to require provenance + SBOM + signature before promoting an image.

## Notes

This is a scaffold to get started quickly. For production, use formal SLSA tooling and well-defined builder identities (not ad-hoc scripts). See issue #213 for tracking full SLSA integration.
