Title: Enforce policy — No GitHub Actions workflows in this repository

Summary:
This repository must not contain GitHub Actions workflows (`.github/workflows/*`). All CI/CD automation is provided via GitLab CI and our self-hosted runner platform. This issue tracks enforcement steps and remediation guidance.

Policy:
- GitHub Actions workflows are disallowed. Any `.github/workflows/*` files found in commits or branches shall be removed and the change reverted.
- CI automations must be implemented as GitLab CI jobs and use the provided self-hosted runners.
- No GitHub pull-release workflows or GitHub Actions-based releases are permitted.

Enforcement actions implemented:
- Added a GitLab CI job `prohibit:github_actions` which fails pipelines if any `.github/workflows` files are present.
- Updated CI runbooks to recommend GitLab CI for automation and to use GSM/Vault/KMS for secrets.

Remediation steps for maintainers:
1. If you find `.github/workflows/*` files, remove them and replace automation with equivalent GitLab CI jobs.
2. If workflows were ever committed historically, follow the secret/history purge process if they contained secrets and rotate any affected credentials.
3. Notify the security team if a workflow was used to run sensitive operations.

Owner: @admin-team
