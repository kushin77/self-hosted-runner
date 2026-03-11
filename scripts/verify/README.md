Smoke test for Secrets Orchestrator
=================================

This is a CI-free smoke test that runs the local health-check in dry-run
mode and ensures the mirror script processes at least one secret.

Run locally:

```bash
scripts/verify/smoke_check.sh
```

Artifacts are written to `artifacts/verify/`.
