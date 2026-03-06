# Task: Prototype and harden self-hosted runner image

- Related Epic: SOV-004
- Status: in-progress
- Owner: Infra

## Objective
Create a Packer-based immutable runner AMI with Docker, buildx, hardened OS settings, and idempotent bootstrap for registration.

## Checklist
- [x] Add Packer scripts to install Docker (`packer/scripts/install-docker.sh`).
- [x] Add Packer script to install runner binaries (`packer/scripts/install-runner.sh`).
- [x] Add security hardening script (`packer/scripts/harden-security.sh`).
- [x] Add runtime bootstrap script (`tools/runner/bootstrap.sh`).
- [ ] Create Packer build pipeline and CI job to publish AMI.
- [ ] Validate image in staging account.
- [ ] Update `terraform/modules/ci-runners` to reference new AMI and bootstrap user-data.

## Notes
Pushed initial artifacts on branch `sov/runner-image-hardening`.
