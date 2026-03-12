Title: Review & merge: elite GitLab MSP ops control plane

Description:
This issue tracks review and merge of the `elite/gitlab-ops-setup` branch which adds a full MSP-grade GitLab CI control plane, self-hosted runner skeleton, security policies, k8s manifests, and observability configuration.

Tasks:
- [ ] Security review of pipeline and scripts
- [ ] Validate OPA policies and CI scans
- [ ] Verify no secrets present in repo
- [ ] Test runner bootstrap in isolated environment
- [ ] Approve and merge PR `elite/gitlab-ops-setup` → `main`

How to run locally:
- Clone and inspect branch:

  git fetch origin elite/gitlab-ops-setup
  git checkout elite/gitlab-ops-setup

- Run the setup script on an isolated host (review first):

  chmod +x scripts/ops/setup-elite-gitlab.sh
  ./scripts/ops/setup-elite-gitlab.sh

Notes:
- Automated remote issue/PR creation requires a `GITHUB_TOKEN` with `repo` scope. Provide a token if you want this assistant to open the PR and create this issue automatically.
