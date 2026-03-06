# Task: Add Vault helper scripts and secrets-scan workflow

- Related Epic: SOV-006
- Status: in-progress
- Owner: Security/Infra

## Objective
- Provide a minimal helper to fetch secrets from Vault for CI workflows.
- Add a repository secrets-scan workflow using `gitleaks` to detect accidental secret commits.

## Checklist
- [x] Add `ci/scripts/fetch-vault-secret.sh`.
- [x] Add `.github/workflows/secrets-scan.yml`.
- [x] Add `docs/VAULT_INTEGRATION.md` guidance.
- [ ] Configure CI service principal/approle for Vault access.
