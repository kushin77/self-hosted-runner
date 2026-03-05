# Contributing to self-hosted-runner

This repository runs CI on local, organization-controlled self-hosted GitHub Actions runners. All contributors must follow the rules below to keep CI secure, reliable, and auditable.

## Required Workflow Rules
- All GitHub Actions workflows MUST use `runs-on: [self-hosted, linux]` (or a specific self-hosted label defined by ops).
- Use `workflow_dispatch` only where manual dispatch is appropriate; otherwise rely on branch or tag triggers.
- Avoid using `ubuntu-latest`, `windows-latest`, or `macos-latest` in this repository.

## Secrets & Credentials
- Do NOT place secrets in repository files or artifacts. Use one of:
  - GitHub Repository/Environment secrets
  - Vault (preferred) and fetch at runtime using the approved vault helper scripts
- Runner-level sensitive files (SSH keys, cloud creds) must be stored on the runner host and access-controlled by OS-level permissions; document their location in the ops runbook (not in Git).

## PR / Review Policy
- All changes to workflows, runner configuration, and provisioning code MUST have at least one review from a code owner listed in `.github/CODEOWNERS`.
- Changes that modify runner labels, provisioning, or secrets handling MUST include an Ops approval (add `ops` reviewer or tag).
- Tests that exercise CI behavior should be added to the relevant `test-suite.yml` or as a separate workflow that runs on the self-hosted runner.

## Branch Protection and Enforcement
- Enable branch protection on `main` (or default branch): require status checks, PR reviews, and restrict who can push.
- Protect secrets and environments with approval gates where required (see `docs/PHASE_P4_AWS_SPOT_VERIFICATION.md` for pattern).

## Runner Maintenance and Updates
- Keep the `actions-runner` binary under `actions-runner/` updated regularly; use the release notes to verify compatibility.
- If you are an ops engineer running a host, document upgrades, service restarts, and maintenance windows in `docs/SELF_HOSTED_MIGRATION_SUMMARY_2026.md` and the ops runbook.

## Troubleshooting & Monitoring
- Runner logs are stored at `/tmp/runner.log` on the host by default. Use the `monitoring` scripts in `scripts/` to collect and push logs to the central observability stack.
- If a workflow does not start, check the runner status and labels: `ps aux | grep Runner.Listener` and `tail -f /tmp/runner.log`.

## Non-Compliance
- Pull requests that reintroduce hosted-runner labels will be blocked by automated governance checks and returned for revision.
- Repeated or dangerous non-compliance (exposing secrets, bypassing review) may result in temporary commit access revocation.

## Contact / Support
- For runner/operator issues, open an issue with label `ops` and include `runner-<hostname>` and recent log excerpts.
- For policy exceptions, request an exception via an issue and tag `security` and `ops` for review.

Thank you for keeping CI secure and reliable.
