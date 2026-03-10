# Issue #2274 — Monthly NO GitHub Actions Compliance (OPEN)

Status: OPEN

Schedule: 1st Friday of each month

Purpose: Verify repository contains ZERO GitHub Actions workflows and that enforcement mechanisms are active.

Checks:
- `.githooks/prevent-workflows` exists and is executable
- `git config core.hooksPath` == `.githooks`
- `find .github/workflows -name "*.yml" | wc -l` == 0
- `.instructions.md` contains NO GITHUB ACTIONS mandate

Remediation: Archive any workflows found, commit the archive to `docs/archive/`, and update `.instructions.md` and pre-commit hooks.
