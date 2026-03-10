# Release Promotion Staging Test

Use this guide to run a safe, manual smoke-test of the release promotion flow against a staging registry.

Prerequisites:
- Configure repository secrets: `TARGET_REGISTRY_STAGING`, `TARGET_REGISTRY_STAGING_USERNAME`, and `TARGET_REGISTRY_STAGING_PASSWORD` (if registry requires auth).
- Runner must be allowed to push to the staging registry.

How it works:
- The workflow `.github/workflows/ci-release-promotion-staging.yml` is manual (`workflow_dispatch`).
- It generates the image manifest and attempts a conservative test push of the first image in the manifest to the staging registry.
- This is intended as a human-triggered smoke test before enabling automated promotion in production.

Run the test from GitHub Actions UI or using `gh`:

```bash
gh workflow run ci-release-promotion-staging.yml --repo <owner/repo>
```

Notes:
- The workflow pushes only the first image as a smoke test; if success, you can adapt to push all images.
- Use this workflow to validate registry credentials, network access, and that the `promote_release.sh` logic works in your environment.
- Cleanup (removing test images) must be done via your registry UI/API; the test does not auto-delete pushed images.
