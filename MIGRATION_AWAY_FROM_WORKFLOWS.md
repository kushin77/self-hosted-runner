Migration: Move off GitHub Workflows and PR-based automation
-------------------------------------------------------

Summary
- All automated triggers (scheduled and pull-request-driven) have been disabled in workflows.
- Workflows moved to manual-only runs via `workflow_dispatch` or archived under `.github/workflows/.disabled/`.

What changed
- Updated active workflows to require manual dispatch instead of running on schedules or PR events.

Why
- Direct development and deployment model requested: stop PR-driven automation and CI workflows.

How to run previously-automated jobs
- Use GitHub Actions UI -> Actions -> select workflow -> "Run workflow" (choose inputs if applicable).
- Or run equivalent scripts locally or on your deployment runner (see `scripts/` and `deploy.sh`).

Rollback
- To re-enable scheduling or PR triggers, restore the original `on:` section from repo history or move files back from `.github/workflows/.disabled/`.

Notes
- Dependabot and other automation may already be archived in `.github/.disabled/` as part of prior steps.
- Review `CODEOWNERS` and contribution docs if you want to remove auto-assign behavior.
