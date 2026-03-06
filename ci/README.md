CI migration helpers
====================

This folder contains scripts and guidance to replace external GitHub Actions with in-repo scripts suitable for self-hosted runners.

Usage guidance
--------------
- `ci/scripts/setup-node.sh` — installs Node.js (NODE_VERSION env var optional).
- `ci/scripts/setup-buildx.sh` — installs Docker Buildx plugin.
- `ci/scripts/login-registry.sh` — logs into a registry using `REGISTRY_URL`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`.

Best practices
--------------
- Fetch secrets from Vault at runtime; do not hardcode credentials.
- Add idempotent checks to ensure scripts are safe to re-run.
- Integrate these scripts into workflows only for self-hosted runners. Keep GitHub-hosted workflows unchanged for cloud users.
