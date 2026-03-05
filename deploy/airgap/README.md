# Air-gap Image Manifest

This folder contains basic helpers and a manifest skeleton used to collect/service images required for air-gapped deployments.

Usage:

- `scripts/airgap/generate_image_manifest.sh` will emit a YAML manifest listing images used by this repository (example output).

Follow-ups (issue #193): finalize list, add image checksums, and add automation to pull/save images.
