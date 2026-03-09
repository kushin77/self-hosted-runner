# Contributing to self-hosted-runner

> **NOTICE (CI/CD Paused)** — As of 2026-03-09 CI/CD operations are temporarily paused and all GitHub Actions workflows have been removed from `main` and archived. Use the archive branches (archive/workflows-*) or the artifacts in `/tmp` to review previous workflows. See issue: https://github.com/kushin77/self-hosted-runner/issues/2064 for details. Do NOT reintroduce workflows or re-register runners without explicit Ops authorization.

This repository previously ran CI on local, organization-controlled self-hosted GitHub Actions runners. CI-related rules below are temporarily suspended while workflows remain archived; re-enablement will be coordinated by Ops and communicated in the emergency issue above.

## Required Workflow Rules (TEMPORARILY PAUSED)
- CI workflows are archived and NOT present on `main`. Do NOT add, modify, or re-enable workflows until Ops authorizes reactivation.
- When CI is re-enabled, workflows must follow the original rules: prefer `runs-on: [self-hosted, linux]` (or an ops-approved label), use `workflow_dispatch` sparingly, and avoid `*-latest` runners unless explicitly approved.

## Secrets & Credentials

### Core Rules
- **NEVER** commit secrets to git. Use proper secret management tools instead.
- **NEVER** print secrets in logs. GitHub masks secrets by default (`***`), but ensure no raw values appear.
- **NEVER** hardcode credentials in YAML/scripts. Always use `${{ secrets.SECRET_NAME }}` syntax.
- **NEVER** share secrets via Slack, email, or GitHub comments.

### Where to Store Secrets
Use this decision tree for each new secret:

```
Repo-level secret (used in this repo only)?
  → Use GitHub Secrets (Settings → Secrets)
  → Set with: gh secret set SECRET_NAME --repo kushin77/self-hosted-runner

Shared across multiple repos?
  → Use Google Secret Manager (GSM, gcp-eiq project)
  → Set with: gcloud secrets create secret-name --data-file=- --project=gcp-eiq

Requires dynamic rotation (< 24h lifetime)?
  → Use HashiCorp Vault (preferred)
  → See: docs/VAULT_GETTING_STARTED.md

Runner-level files (SSH keys, configs)?
  → Store ON RUNNER HOST (not in Git)
  → Access-control with OS permissions
  → Document location in ops runbook only
```

### Adding a New Secret
1. **Find it**: `bash scripts/audit-secrets.sh --search "PATTERN"` to see existing secrets
2. **Index it**: Read [SECRETS_INDEX.md](SECRETS_INDEX.md) — all secrets are cataloged here
3. **Add it**: Create secret, update documentation
4. **Validate it**: `bash scripts/audit-secrets.sh --validate` before creating a draft issue for deployment
5. **Reference it**: The draft issue or deployment record must include a link to [SECRETS_INDEX.md](SECRETS_INDEX.md) updates

### Required Reading Before Adding Secrets
- **[SECRETS_INDEX.md](SECRETS_INDEX.md)** — Complete catalog + how to search programmatically
- **[DEVELOPER_SECRETS_GUIDE.md](DEVELOPER_SECRETS_GUIDE.md)** — Step-by-step guide for developers
- **[SECRETS_SETUP_GUIDE.md](SECRETS_SETUP_GUIDE.md)** — Configuration & troubleshooting

### Rotation Schedules
- **30-90 days**: SSH keys, API keys, database passwords, OAuth tokens
- **180 days**: Service account keys, SMTP credentials, MinIO keys, webhooks
- **365 days**: Project IDs, OIDC endpoints, configuration URLs (reference data)
- **24 hours** (auto): Vault Secret IDs (handled by Vault)

### Most Common Secrets

| Secret | Where | Access | Rotation | Use Case |
|--------|-------|--------|----------|----------|
| `DEPLOY_SSH_KEY` | GitHub | `gh secret list` | 90d | Ansible SSH authentication |
| `RUNNER_MGMT_TOKEN` | GitHub | `gh secret list` | 90d | GitHub API access |
| `AWS_OIDC_ROLE_ARN` | GitHub | `gh secret list` | Never | Terraform AWS access (OIDC) |
| `GCP_PROJECT_ID` | GitHub | `gh secret list` | Never | GCP project identifier |
| `terraform-aws-prod` | GSM | `gcloud secrets list` | 90d | AWS Access Key (Terraform) |
| `MINIO_*` | GitHub | `gh secret list` | 180d | Artifact storage (S3-compatible) |
| `VAULT_ROLE_ID` | GitHub | `gh secret list` | Never | Vault AppRole ID |

### Valid Workflow Syntax Examples

✅ **Correct** — Secret used in step environment:
```yaml
- name: Deploy
  env:
    API_KEY: ${{ secrets.API_KEY }}
  run: curl -H "Authorization: $API_KEY" https://api.example.com
```

❌ **Wrong** — Secret in top-level env:
```yaml
env:
  API_KEY: ${{ secrets.API_KEY }}  # Not masked properly at top
```

❌ **Wrong** — Hardcoded value:
```yaml
run: curl -H "Authorization: hardcoded-key-12345" https://api.example.com
```

### Audit & Validation
Before opening a PR, verify your changes:
```bash
# See all secrets and their usage
bash scripts/audit-secrets.sh --full

# Check if required secrets are configured
bash scripts/audit-secrets.sh --validate

# Search for specific secret
bash scripts/audit-secrets.sh --search "GCP_"

# Generate JSON manifest (for CI integration)
bash scripts/audit-secrets.sh --json > secrets-manifest.json
```

### Troubleshooting Secrets
- **Secret not found**: `gh secret list --repo kushin77/self-hosted-runner`
- **OIDC failing**: See [DEVELOPER_SECRETS_GUIDE.md](DEVELOPER_SECRETS_GUIDE.md#troubleshooting)
- **GSM access denied**: Check service account has `roles/secretmanager.secretAccessor`
- **Rotation overdue**: Check [SECRETS_INDEX.md](SECRETS_INDEX.md) rotation schedule

## Change & Review Policy (PRs Deprecated)
- Pull requests are deprecated while CI/CD is paused. All proposed changes must be recorded as a draft issue and reference the emergency record `#2064`.
- For operational changes (deployments, runner updates, secrets), open a draft issue and include: deployer username, UTC timestamp, bundle SHA256, and a pointer to logs; then perform the approved direct-deploy to `192.168.168.42`.
- When CI is re-enabled, the team will reconvene to agree the PR process and reinstate any governance rules.

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

## Direct Development & Deployment (MANDATED)

- Effective immediately, authorized development and deployment activity for this repository SHALL be performed directly on the approved worker node at 192.168.168.42. This is a temporary operational directive while CI/CD is paused.
- Do NOT attempt to re-enable or rely on GitHub Actions workflows in this repository until Ops signals reactivation.
- Who may deploy: only users with explicit Ops authorization and SSH access to `192.168.168.42` (use the `deploy` account or the account specified by Ops). All deployments must be performed over SSH using approved tooling (`rsync`, `scp`, or the documented `deploy.sh` helper) and must use ephemeral credentials fetched via GSM/VAULT/KMS.
- Required steps for a direct deploy:
  1. Create a branch for the change and open a draft issue referencing the emergency record `#2064`.
  2. Run local validation and unit tests on your workstation.
  3. Prepare a deployment bundle (tar.gz) and an integrity hash (SHA256).
  4. Transfer the bundle to `192.168.168.42` via `scp`/`rsync` and verify the SHA256 on the node.
  5. On `192.168.168.42`, run the documented deploy script `./deploy.sh` (or Ops-approved alternative). Capture and upload deployment logs to the central observability store and reference them in the associated issue.
  6. Close or update the draft issue with deployment outcome and artifact links.
- Secrets and credential handling: all credentials used on `192.168.168.42` must be fetched at runtime via GSM/VAULT/KMS; never embed secrets in the bundle or in plain text on the host.
- Audit and logging: every direct deployment MUST be recorded in an issue and include the deployer username, UTC timestamp, bundle SHA256, and a pointer to logs.

Non-compliance: unauthorized direct deploys or attempts to reintroduce workflows will be treated as policy violations and may result in temporary access revocation. If you require an exception, open an issue and tag `ops` and `security`.
