# Initiative: Make build Immutable, Ephemeral, Idempotent, Fully Automated

Goal
---
Make the repository and deployment pipeline conform to the following principles:
- Immutable: deployed artifacts are read-only and replaced (no in-place edits).
- Ephemeral: runtime state is stored under `/run` and cleaned on restart; services are disposable.
- Idempotent: repeated runs produce the same state (no destructive side-effects on re-run).
- Fully automated & hands-off: CI/CD handles deploys without human interaction once creds/ops steps are done.

Scope
---
- Ansible playbooks and roles
- Systemd unit templates and tmpfiles
- CI workflows (PR preflight + deploy automation)
- Secrets management (use Vault AppRole; no secrets in repo)
- Observability checks (metrics verification post-deploy)

Planned Tasks
---
- [ ] Add PR preflight workflow to run linters, `ansible --syntax-check`, and hardening checks.
- [ ] Add a small `scripts/check_hardening.sh` that validates `ProtectSystem`, `ReadOnlyPaths`, and `tmpfiles` usage in templates.
- [ ] Ensure `ansible/playbooks/deploy-rotation.yml` uses atomic copy to `/usr/libexec` and runtime dirs under `/run` (already mostly done; verify).
- [ ] Ensure systemd templates include `ProtectSystem=strict|full`, `ReadOnlyPaths`, `NoNewPrivileges`, `ProtectHome=true`.
- [ ] Integrate Vault AppRole for secrets (workflow PR #708 already prepares this).
- [ ] Add an automated idempotence test job that runs `ansible-playbook` twice in check mode and verifies no changes on second run.
- [ ] Add automated metric verification step post-deploy (query Prometheus or exported endpoint).
- [ ] Document runbooks and add rollback steps.

Acceptance Criteria
---
- New PRs run preflight and fail when checks don't pass.
- Deploy workflow runs non-interactively via Vault AppRole and passes checks.
- Post-deploy metric checks verify rotation success.

Next Steps
---
I will add the preflight workflow and `scripts/check_hardening.sh` in a branch and open PR `chore/preflight-hardening` including this issue for tracking.
Once the PR is merged, we'll enable the workflow and continue with idempotence tests and metric verification.
