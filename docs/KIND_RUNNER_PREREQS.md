# Kind & Runner Prerequisites

This supplement explains how to prepare a self-hosted runner for `kind`-based tests (e.g. `harbor-integration-smoke.yml`).

## Requirements

- **Docker**: a working Docker engine. `kind` relies on Docker to spawn clusters. Any recent version (>=20.10) is acceptable; the repository's CI uses `docker` CLI available on `ubuntu-latest` and self-hosted images.
- **Network**: outbound HTTPS access to `github.com` to download `kind` binaries and container images.

## Installation

The repository provides `ci/scripts/setup-kind.sh` which installs a pinned `kind` binary (default v0.20.0) if not already present:

```bash
chmod +x ci/scripts/setup-kind.sh
./ci/scripts/setup-kind.sh v0.20.0   # version optional
``` 

The script handles architecture detection and places the binary in `/usr/local/bin` (or `~/.local/bin` when sudo is unavailable).

## Usage in workflows

`harbor-integration-smoke.yml` and similar workflows now include a step:

```yaml
- name: Install kind
  run: |
    chmod +x ci/scripts/setup-kind.sh
    ./ci/scripts/setup-kind.sh
```

The step runs only on self-hosted runners; hosted runners use the marketplace action as a fallback.

## Validation

To validate on staging:

1. Ensure Docker is installed and running on the staging runner.
2. Run the workflow `harbor-integration-smoke.yml` manually or via a PR.
3. Confirm `kind` is installed and a temporary cluster is created during the run.

Once validated, this pattern can be applied to other `kind`-dependent workflows.
