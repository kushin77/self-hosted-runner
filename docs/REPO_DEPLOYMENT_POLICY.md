Repository Deployment Policy — enforced (immutable/ephemeral/idempotent/no-ops)

Goal
- Enforce direct development and direct deployment via Cloud Build (no GitHub Actions, no GitHub release workflows).
- All credentials stored in GSM (GCP Secret Manager), Vault, or KMS; no long-lived secrets in repo.
- Infrastructure and deployments are idempotent and immutable: use Terraform with state locking and artifact pinning.
- Fully automated, hands-off deployments: Cloud Build (or equivalent CI) triggers from `main` only.

Policy Rules
1. No GitHub Actions workflows
   - Remove or archive any files in `.github/workflows/`.
   - Repository setting: disable GitHub Actions or restrict to allow only approved workflows (org-admin).
2. Direct deployment only
   - Commits to `main` trigger Cloud Build pipeline that runs tests, builds images, SBOM, scans, signs images, and deploys.
   - No release PRs or GitHub-based release flows.
3. Secrets management
   - Use GSM / Vault / KMS for all credentials and signing keys.
   - No plaintext secrets in code, docs, or CI variable definitions in GitHub.
4. Immutable artifact storage
   - Push images to Artifact Registry with digest pinning; enable S3/GCS object lock for compliance artifacts where required.
5. Idempotency
   - Terraform plans must be reviewed but `apply` should be idempotent; use state locking and automated plan gating.
6. Observability + Audit
   - All deployments and SBOM/scan outputs must be archived (GCS) and GPG-signed or stored with object lock.
7. Branch protection and approvals
   - `main` is protected: require `CODEOWNERS` approvals and pass status checks.

Operational Steps to Enforce
- Remove existing workflows from `.github/workflows` or move into `archived_workflows/` (we found archived_workflows already in repo).
- Add `CODEOWNERS` (this PR) to require ops/platform approval for merges.
- Repo admins: disable GitHub Actions or restrict usage in repository settings.
- Configure Cloud Build triggers for `main` and ensure the Cloud Build SA has necessary permissions for artifact storage and rollout.
- Ensure GSM/Vault/KMS are configured and secrets migrated. Update CI templates to reference GSM/Vault paths.

How to migrate secrets from GitHub Actions variables (example)
1. Create secret in GSM/Vault/KMS
2. Update Cloud Build trigger to use `availableSecrets` pointing to GSM secret
3. Remove the GitHub variable and document change in PR

Example Cloud Build substitution for secrets (cloudbuild.yaml):

```
availableSecrets:
  secretManager:
    - versionName: "projects/$PROJECT_ID/secrets/GITHUB_TOKEN/versions/latest"
      env: "_GITHUB_TOKEN"
```

Enforcement Criteria
- No active workflow files in `.github/workflows/` (or marked archived)
- `main` branch requires `CODEOWNERS` approval and status checks
- Cloud Build triggers exist and are documented in `docs/CI_UPLOAD_INSTRUCTIONS.md`
- Secrets migrated to GSM/Vault/KMS

If you want, I will:
- Open a follow-up issue asking repo admins to disable GitHub Actions in repository settings.
- Provide a small migration script to detect secrets in repo history and suggest migration steps.

Contact: @kushin77 (ops), @BestGaaS220 (tech lead)
