# Deprecate Pull Requests (Operational Directive)

Action taken: Draft issue workflows and templates are deprecated. The repository will not use Draft issues while CI/CD is paused. All dependency automation and PR-creating automation has been disabled or archived.

Changes applied in branch `ops/enforce-deploy-host-192-168-168-42`:

- Disabled GitHub Actions workflows (moved to `.github/workflows/.disabled/`)
- Disabled Dependabot (moved to `.github/.disabled/dependabot.yml`)
- Removed CODEOWNERS entry referencing `.github/PULL_REQUEST_TEMPLATE.md`
- Updated `CONTRIBUTING.md` to deprecate Draft issues and replace PR instructions with draft-issue + direct-deploy flow

Operational guidance summary:

- All changes must be tracked in a draft issue and deployed directly to `192.168.168.42` by authorized operators.
- Do not open Draft issues or rely on GitHub Actions for deployments while this directive is active.
- Maintain immutable audit trails: every deploy must include deployer username, UTC timestamp, bundle SHA256, and links to logs and artifacts.

If you want me to also:
- Remove PR references across docs (large sweep) and update historical docs, or
- Create a small script to scan and auto-update doc references to PR -> draft issue,
please say so and I will proceed.
