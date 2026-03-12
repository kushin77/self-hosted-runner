CI/CD Policy — Cloud Build required

Summary
- Cloud Build is the canonical CI/CD system for this repository.
- Cloud Build triggers should be configured to run on commits to `main` and on tag patterns, where appropriate.

Secrets
- Use Google Secret Manager (GSM) or HashiCorp Vault for all secrets.
- DO NOT store credentials in repo, env files, or GitHub Actions secrets.

Deployments
- Deployments are direct: commit -> Cloud Build -> Cloud Run/K8s.
- No GitHub Actions, no GitHub release automation.

How to run locally (dev)
- Use `make test` or `go test ./...` locally. Build artifacts should be produced with `docker build` and validated with `syft`/`trivy` on approved hosts.

Ops contact
- @kushin77 and @BestGaaS220 are primary owners for CI/CD policy.