# Cloud Build & Branch Protection Setup (admins)

Follow these steps to configure Cloud Build triggers and GitHub branch protection for the `main` branch.

1. Create Cloud Build trigger for policy check (block workflows):

```bash
gcloud beta builds triggers create github \
  --name="policy-check-trigger" \
  --repo-owner="kushin77" \
  --repo-name="self-hosted-runner" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild/policy-check.yaml"
```

2. Create Cloud Build trigger for direct-deploy pipeline:

```bash
gcloud beta builds triggers create github \
  --name="direct-deploy-main" \
  --repo-owner="kushin77" \
  --repo-name="self-hosted-runner" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild/direct-deploy.yaml" \
  --substitutions="_SERVICE_NAME=nexus-normalizer,_REGION=us-central1"
```

3. Configure GitHub branch protection (requires repo admin/owner):

Use the GitHub API or the web UI to require status checks from Cloud Build and to block changes that add `.github/workflows` files. Example `gh` commands:

```bash
# Require Cloud Build status check (replace CONTEXT with exact check name)
gh api --method PUT \
  -H "Accept: application/vnd.github+json" \
  /repos/kushin77/self-hosted-runner/branches/main/protection \
  -f required_status_checks.contexts='["cloudbuild/build"]' \
  -f enforce_admins=true \
  -f required_pull_request_reviews.dismiss_stale_reviews=true
```

For a pre-receive enforcement to block `.github/workflows` you may use an organization pre-receive hook or rely on the Cloud Build `policy-check` trigger set as a required status check.

4. Secrets & Permissions

- Ensure Cloud Build service account has `roles/run.admin`, `roles/storage.admin` (for pushing images), and access to GSM/Vault/KMS secrets.
- Grant `storage.objects.get` to `deployer-run` SA as required (see issue #2684).

5. Testing

- Push a harmless change to `main` and confirm both triggers run.
- Attempt to add a file under `.github/workflows/` and verify the `policy-check` trigger fails the build.

