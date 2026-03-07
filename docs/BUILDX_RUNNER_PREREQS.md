# Docker Buildx & Runner Prerequisites

This document outlines requirements for self-hosted runners that need Docker Buildx for multi-platform builds.

## Requirements

- **Docker CLI ≥ 20.10**: Buildx is a plugin for Docker; the CLI must support plugin directories. Most modern Docker installations already meet this.
- **Docker daemon**: running and accessible to the runner user.
- **Network access**: outbound to `github.com` to download Buildx binaries.

## Installation

The repository provides `ci/scripts/setup-buildx.sh` which will:

1. Detect whether `docker buildx` is already available.
2. If not, fetch the latest Buildx release from GitHub, extract the `docker-buildx` binary, and place it in the appropriate `cli-plugins` directory (`/usr/local/lib/docker/cli-plugins` or `$HOME/.docker/cli-plugins`).
3. Make the plugin executable.

Usage in workflow steps:

```yaml
- name: Install docker buildx
  run: |
    chmod +x ci/scripts/setup-buildx.sh
    ./ci/scripts/setup-buildx.sh
```

This step should run before any `docker buildx` commands in self-hosted workflows. Hosted runners can continue using the official `docker/setup-buildx-action` as a fallback.

## Validation

1. Run a workflow that invokes `docker buildx` (e.g. `harbor-integration-smoke.yml` or `p2-vault-integration.yml`).
2. Confirm the log shows `docker buildx already available` or `Installed docker buildx:` after script execution.

Once validated on staging, the pattern can be applied to other repository workflows.
