## No GitHub Actions Policy

This repository enforces direct deployment via Cloud Build and operator automation.

Please do not add GitHub Actions workflows. All CI/CD must be implemented using the approved control plane (Cloud Build) and in-repo scripts invoked by Cloud Build or the agent.

If you need a new build step, open an issue and reference the required Cloud Build config; an ops maintainer will add the Cloud Build trigger.
# GitHub Actions Disabled — Cloud Build Only Policy

**Effective date:** March 12, 2026  
**Status:** ENFORCED (repo-level disabled)

## Policy

GitHub Actions workflows are **disabled** at the repository level. All CI/CD automation **must** use Cloud Build.

### Why?

1. **Hands-off automation**: Cloud Build integrates directly with Terraform + GCP infrastructure; no GitHub-managed runners needed.
2. **Credential isolation**: Secrets managed via GSM/Vault/KMS, not GitHub Secrets.
3. **Direct deployment**: Commits to `main` → Cloud Build triggers → deployed (no release workflow).
4. **Audit compliance**: All builds logged to Cloud Logging with immutable audit trail (JSONL).

### Enforcement

- ✅ `.github/workflows/` directory is **empty** (all workflows removed).
- ✅ Repository settings: GitHub Actions **disabled**.
- ✅ Branch protection: All tests must come from Cloud Build status checks, NOT GitHub Actions.
- ✅ `.gitignore`: No GitHub Actions-related files can be tracked.

### If you need to add automation:

1. **Do NOT create `.github/workflows/*.yml` files** — they will be rejected at merge time.
2. Instead, create a **Cloud Build trigger**:
   ```bash
   gcloud builds triggers create github \
     --repo-name=self-hosted-runner \
     --repo-owner=kushin77 \
     --branch-pattern='^main$' \
     --build-config=cloudbuild.yaml \
     --name=my-trigger
   ```
3. Add a status check requirement in branch protection to require the Cloud Build trigger to pass.

### Cloud Build status checks required before merge:

All commits to `main` require:
- ✅ Cloud Build (specified trigger) — **REQUIRED**
- ✅ CODEOWNERS approval — **REQUIRED**
- ✅ All conversations resolved — **REQUIRED**

### References

- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Branch Protection Rules](../../.github/BRANCH_PROTECTION.md)
- [Direct Deployment Policy](./DIRECT_DEPLOYMENT_POLICY.md)
- Issue: [#2778](https://github.com/kushin77/self-hosted-runner/issues/2778)
