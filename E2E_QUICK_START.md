# E2E Quick Start

This quick-start gets you from zero to a validated hands-off deploy.

Prereqs
- Repository admin or maintainer permissions
- `gh` CLI configured with an account that can set repository secrets

Steps

1. Add MinIO secrets (replace values):

```bash
gh secret set MINIO_ENDPOINT --body "https://minio.example.com" --repo kushin77/self-hosted-runner
gh secret set MINIO_ACCESS_KEY --body "MINIOACCESS" --repo kushin77/self-hosted-runner
gh secret set MINIO_SECRET_KEY --body "MINIOSECRET" --repo kushin77/self-hosted-runner
gh secret set MINIO_BUCKET --body "github-actions-artifacts" --repo kushin77/self-hosted-runner
```

2. (Optional) Add `VAULT_ADMIN_TOKEN` to enable auto-provisioning:

```bash
gh secret set VAULT_ADMIN_TOKEN --body "s.XXX" --repo kushin77/self-hosted-runner
```

3. (Optional) Add `GITHUB_ADMIN_TOKEN` to allow workflows to persist generated secrets:

```bash
gh secret set GITHUB_ADMIN_TOKEN --body "ghp_XXX" --repo kushin77/self-hosted-runner
```

4. Ensure `deploy-approle` environment has required reviewers (Settings → Environments → deploy-approle).

5. Trigger the E2E workflow (this will validate MinIO and, on success, dispatch the hands-off deploy):

```bash
gh workflow run e2e-validate.yml --repo kushin77/self-hosted-runner --field run_deploy=true
gh run list --repo kushin77/self-hosted-runner --workflow=e2e-validate.yml
gh run view <run-id> --repo kushin77/self-hosted-runner --log
```

Expected outcome
- MinIO upload/download succeed (checksum verified)
- `deploy-rotation-staging` workflow dispatched with `hands_off=true`
- If environment approval is required, approve in the Actions UI to proceed with provisioning

Troubleshooting
- If the E2E step fails at "Validate required secrets", ensure `MINIO_*` secrets are present.
- If MinIO upload fails, verify endpoint reachability and credentials.

If you want me to persist secrets and run the E2E workflow, provide a minimal-scope `GITHUB_ADMIN_TOKEN` and the MinIO values; otherwise ask an admin to add the secrets and reply when done.
# E2E Quick Start for Ops

**Status**: ✅ Ready for provisioning (all automation complete)  
**Blocking item**: ⏳ Vault credentials required on self-hosted runner  
**Primary issue**: GitHub #764 (Ops: Provision Vault/AppRole)  

---

## What Automation Has Been Prepared

All code is in `main` and production-ready. No additional coding required.

| Component | Location | Status |
|-----------|----------|--------|
| E2E script (non-admin) | `scripts/ci/run-e2e-self-hosted-with-vault.sh` | ✅ Ready |
| E2E script (admin auto-provision) | `scripts/ci/provision-approle-and-run-e2e.sh` | ✅ Ready |
| GitHub workflow (manual) | `.github/workflows/self-hosted-e2e.yml` | ✅ Ready |
| GitHub workflow (simulate) | `.github/workflows/self-hosted-e2e-simulate.yml` | ✅ Ready |
| Operator runbook | `docs/E2E_RUNBOOK.md` | ✅ Ready |
| Full documentation | `E2E_EXECUTION_SUMMARY.md` | ✅ Ready |
| Local test harness | `scripts/automation/pmo/tests/test_runner_suite.sh` | ✅ 15/15 passing |

---

## What Ops Needs to Do (Choose One)

### 🅰️ **OPTION A: Admin Auto-Provision (Recommended for first run)**

1. Get a temporary Vault admin token from your Vault admin
2. Export to your environment (or set in runner service):
   ```bash
   export VAULT_ADDR='https://vault.your-domain:8200'
   export VAULT_ADMIN_TOKEN='s.your_admin_token_here'
   ```
3. Run on the self-hosted runner:
   ```bash
   cd /path/to/self-hosted-runner
   ./scripts/ci/provision-approle-and-run-e2e.sh
   ```
4. Script will create AppRole, run tests, then revoke & delete the AppRole
5. Reply to GitHub issue #764: "Admin flow complete"

---

### 🅱️ **OPTION B: Non-Admin Flow (For ongoing runs)**

1. Create or obtain a Vault AppRole with appropriate permissions
2. Set on the self-hosted runner:
   ```bash
   export VAULT_ADDR='https://vault.your-domain:8200'
   export VAULT_ROLE_ID='your_role_id'
   export VAULT_SECRET_ID='your_secret_id'
   ```
   OR place secret in a file:
   ```bash
   echo 'your_secret_id' > /run/secrets/vault_secret_id
   chmod 600 /run/secrets/vault_secret_id
   export VAULT_ADDR='https://vault.your-domain:8200'
   export VAULT_ROLE_ID='your_role_id'
   export VAULT_SECRET_ID_PATH='/run/secrets/vault_secret_id'
   ```
3. Run:
   ```bash
   cd /path/to/self-hosted-runner
   ./scripts/ci/run-e2e-self-hosted-with-vault.sh
   ```
4. Reply to GitHub issue #764: "Non-admin flow complete"

---

### 🅲️ **OPTION C: GitHub Repository Secrets (For automated CI)**

1. In GitHub repo settings (https://github.com/kushin77/self-hosted-runner/settings/secrets):
   ```
   VAULT_ADDR = https://vault.your-domain:8200
   VAULT_ROLE_ID = your_role_id
   VAULT_SECRET_ID = your_secret_id
   ```
   OR (for admin auto-provision):
   ```
   VAULT_ADDR = https://vault.your-domain:8200
   VAULT_ADMIN_TOKEN = s.your_admin_token  (temporary, rotate after first run)
   ```

2. Dispatch workflow:
   ```bash
   gh workflow run .github/workflows/self-hosted-e2e.yml --ref main -f trigger_mode=run
   ```
   OR (for admin flow):
   ```bash
   gh workflow run .github/workflows/self-hosted-e2e.yml --ref main -f trigger_mode=provision
   ```

3. Reply to GitHub issue #764: "GitHub secrets provisioned and workflow dispatched"

---

## Detailed Documentation

For comprehensive details, troubleshooting, and security notes, see:
- **Full guidance**: `E2E_EXECUTION_SUMMARY.md` (top-level in repo)
- **Copy-paste runbook**: `docs/E2E_RUNBOOK.md`

---

## What Happens After Ops Replies to Issue #764

1. ✅ Already: All code committed, tested locally (15/15 tests pass)
2. ✅ Already: Workflows deployed and ready
3. ⏳ **Next**: Ops provisions Vault credentials (any of Options A/B/C above)
4. ⏳ **Next**: Ops replies to GitHub issue #764
5. 🤖 **Auto**: Automation agent will:
   - Re-run the E2E workflow immediately
   - Collect and redact logs
   - Verify success
   - Revoke/delete temporary AppRole if used
   - Close issue #764 with final run report

---

## Questions?

- Review redacted logs: `issues/logs/` in repo root
- Check runbook: `docs/E2E_RUNBOOK.md`
- Inspect automation scripts in `scripts/ci/`
- Reply to GitHub issue #764 with questions/blockers

---

**Last updated**: 2026-03-06  
**All code committed to**: `main` branch  
**Ready for**: Immediate Ops provisioning and E2E runs  
