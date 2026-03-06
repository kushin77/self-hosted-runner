Title: Quarterly DR drill for GitLab + runners + Vault

Goal: Regularly validate disaster recovery procedures by performing a quarterly drill that boots a fresh VM/cluster, runs `bootstrap/restore_from_github.sh`, restores encrypted secrets, re-registers runners, and validates pipelines and Vault access.

Checklist:
- [ ] Define DR drill playbook with exact VM specs and required secrets access. (Blocked — see `issues/904-credentials-for-dr-dryrun.md` for credential guidance)
- [x] Automate the drill using `scripts/dr/drill_run.sh` that provisions a throwaway VM (Cloud or local), runs bootstrap, and posts a short report with RTO/RPO. (implemented: `scripts/dr/drill_run.sh`; note: provisioning step is external)
- [ ] Keep offline copies of Vault unseal keys and gitlab-secrets.json decryption keys for drill.
- [ ] Schedule quarterly run and record results in `docs/DR_RUNBOOK.md`.

Recent activity:
- 2026-03-06: Performed a simulated dry-run (no credentials). Simulation found the expected scripts and performed syntax checks; simulated RTO 45m, RPO 15m. See `docs/DR_RUNBOOK.md` for details. Live dry-run remains pending credentials.

Acceptance criteria:
- Fresh instance boots and runs `YAMLtest-sovereign-runner` successfully.
- Vault-authenticated pipeline can fetch a secret and deploy a sample app.
