# Runner Self-Update (placeholder)

This directory contains a minimal, safe placeholder implementation of a runner self-update subsystem.

Components:
- `check-updates.sh` — checks whether a newer version is available (supports `--remote-version` and `--remote-url`).
- `apply-update.sh` — applies an update (currently a simulated/dry-run implementation).
- `version` — current local version token.

How to test (local):

```sh
# dry-run check
sh ./self-update/check-updates.sh --current self-update/version --remote-version 0.1.1 || true
# simulated apply
sh ./self-update/apply-update.sh --current self-update/version --artifact-url https://example.com/artifact.tar.gz --dry-run
```

Replace these placeholders with real artifact storage, signature verification (e.g., `cosign`), and safe update application steps when moving to production.
