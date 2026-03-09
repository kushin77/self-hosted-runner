# Repository Secrets Required for Phase 2 OIDC/WIF and Rotation

This file documents the repository secrets and minimal operator steps required to enable Phase 2 (OIDC/WIF) infrastructure and credential rotation. Do NOT commit any secret values here — add them via the GitHub repository Secrets UI or the organization secrets APIs.

Required repository secrets (names expected by workflows):

- VAULT_ADDR — Vault address (example: https://vault.example:8200)
- VAULT_ROLE — Vault role name bound to GitHub OIDC
- VAULT_NAMESPACE — (optional) Vault namespace if used
- AWS_ACCOUNT_ID — AWS account for role assumption
- AWS_ROLE_TO_ASSUME — IAM role ARN for GitHub Actions OIDC
- GCP_PROJECT_ID — GCP project id used by GSM
- GCP_SERVICE_ACCOUNT — GCP service account email to impersonate
- GCP_WORKLOAD_IDENTITY_PROVIDER — Workload identity provider resource name
- STAGING_KUBECONFIG_B64 — base64-encoded staging kubeconfig (optional for staging deploy)
- PAGERDUTY_SERVICE_KEY — (optional) PagerDuty integration key for alerts

Operator checklist:
1. Add the secrets above via the GitHub UI or `gh secret set` (no plaintext in commits).
2. Ensure OIDC trust is configured in each cloud provider (AWS IAM role trust, GCP WIF provider, Vault OIDC role).
3. Run the `Validate Credential Providers` workflow or trigger `Validate Credential Providers` in Actions.
4. After validation, comment on issue #2060 with a confirmation so we can re-run Phase 2 automation.

If you want me to add the wording to other docs or create a follow-up issue to track secret addition per environment (staging/prod), say so and I'll open it.
