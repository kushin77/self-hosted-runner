# CI/CD Policy

## Enforcement

- **GitHub Actions:** DISABLED (no workflows allowed)
- **CI/CD System:** Cloud Build only
- **Trigger:** Direct pushes to main branch
- **Orchestration:** Terraform via Cloud Build

GitHub Actions must NOT be used in this repository.
All deployments flow through Cloud Build.

## Cloud Build Triggers

See: cloudbuild-*.yaml files for deployment configuration.

Triggers:
- nexus-main-push: Automatic on push to main
- nexus-release-tags: Automatic on semver tags
- nexus-manual-deploy: Manual trigger for emergency deployments
