Title: feat: elite GitLab MSP ops control plane

Summary:
Adds an enterprise-grade GitLab CI configuration and supporting artifacts to bootstrap an MSP ops control plane using self-hosted runners. Key additions:
- `.gitlab-ci.elite.yml` → full 10-stage pipeline (validation, security, build, test, scanning, deploy, observability, audit)
- `.gitlab-runners.elite.yml` → runner definitions and registration helpers
- `policies/` → OPA policies for container and deployment security
- `k8s/` → deployment strategies and scripts (blue/green, canary)
- `monitoring/` → Prometheus/Grafana/Jaeger configs + SLOs
- `scripts/ops/setup-elite-gitlab.sh` → interactive runner/bootstrap setup script
- `ci/4-layer-prompt.md` and `cicd-runner-platform/*` → AI prompt + runner bootstrap skeleton

Notes and required follow-up:
- The branch `elite/gitlab-ops-setup` contains all files and is pushed to origin.
- This PR intentionally excludes a flagged binary (`nexus-engine/bin/ingestion`) which was unstaged due to pre-commit credential detector.
- To create the remote PR automatically, provide a short-lived `GITHUB_TOKEN` (repo scope) or run the following locally:

  gh pr create --title "feat: elite GitLab MSP ops control plane" --body "$(cat PR_BODY.md)" --base main --head elite/gitlab-ops-setup

Testing/Validation steps for reviewers:
1. Inspect `.gitlab-ci.elite.yml` for policy/tooling used (Semgrep, Trivy, Checkov, syft, cosign).
2. Review `scripts/ops/setup-elite-gitlab.sh` and `cicd-runner-platform/bootstrap/bootstrap.sh` before executing on an isolated host.
3. Validate OPA policies under `policies/` with `opa test` and run `trivy filesystem` scans locally if desired.

Merge checklist:
- [ ] Security review of pipeline and runner registration flow
- [ ] Validate no credentials in committed files
- [ ] Confirm deployment and registry credentials are set via CI variables
- [ ] Optional: attach short-lived token for automated PR creation and CI run

Maintainer contact: @akushnir
