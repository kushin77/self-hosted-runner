Repository Policy: No GitHub Pull Releases

This repository enforces a no-pull-releases policy to ensure all deployments go through Cloud Build and GSM/KMS-managed secrets.

## Enforcement

1. **Disable GitHub releases:** Go to Settings > General > Features and uncheck "Releases".
2. **Branch protection:** Cloud Build status checks are required before merge to `main` (prevents unvetted changes from becoming releases).
3. **Direct deployment only:** Use `scripts/ops/deploy_complete.sh` + Cloud Build triggers for all production changes.
4. **CI/CD:** All artifact publishing must use Cloud Build and signed registries (e.g., Artifact Registry with KMS signing).

## Why No Pull Releases?

- Pull releases bypass code review and Cloud Build CI/CD.
- Credentials and secrets may be exposed in release artifacts if not properly managed.
- Releases should only occur after Cloud Build verification and KMS-signed artifacts.

## Artifact Management

- Container images: Push to Artifact Registry via Cloud Build with KMS signature verification.
- Binaries: Publish via Cloud Build to signed artifact repository.
- Documentation: Published via direct Cloud Build job (not GitHub Releases).

## Compliance

Ops/admins: After Phase0 deployment, verify:
```bash
# Releases feature should be disabled
gh repo view --json repositoryTopics --jq '.repositoryTopics'
```

If releases are still enabled, disable them in Settings > General > Features.
