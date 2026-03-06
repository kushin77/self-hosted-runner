# Task: CI steps to publish images and artifacts to internal registry/MinIO

- Related Epic: SOV-005
- Status: in-progress
- Owner: Platform

## Objective
Add a workflow to build container images, push to the internal registry, and upload build artifacts to MinIO.

## Checklist
- [x] Add `.github/workflows/publish-artifacts.yml` (manual dispatch).
- [ ] Add automated triggers (on release or main push) after validation.
- [ ] Add CI smoke tests to validate pulled images from registry.
