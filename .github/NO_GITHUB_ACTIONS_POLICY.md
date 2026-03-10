Repository policy: No GitHub Actions

Policy:
- GitHub Actions workflows are disallowed in this repository by policy.
- All CI/CD and deployment automation must run from self-hosted runners or other approved systems.

Enforcement:
- This repository includes a `githooks/prevent-workflows` script that rejects commits which add or modify `.github/workflows`.
- Organization/repo owners should disable Actions in repo settings and/or at org level for defense-in-depth.

If you are an operator and need to run automation, follow the documented patterns:
- Use the `scripts/auto_gcp_admin_provisioning.sh` and `scripts/finalize_credentials.sh` helpers.
- Use Workload Identity Federation or GSM/Vault/KMS for credentials (no long-lived service account keys checked into git).

Contact: ops@nexusshield-prod for exceptions (requests must be approved and logged in logs/).
