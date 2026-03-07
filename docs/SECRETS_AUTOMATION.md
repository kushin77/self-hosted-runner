# Secrets Automation & Ops Instructions

This document lists repository secrets required for hands-off automation and how to provision them safely.

Required secrets
- `DEPLOY_SSH_KEY` — OpenSSH private key (PEM or OpenSSH format). Used by Ansible runs for canary/progressive rollouts.
- `PAGERDUTY_TOKEN` — PagerDuty API token (v2) with `incidents:write` scope. Used for automated escalation.
- `COSIGN_PRIVATE_KEY` — Base64-encoded PEM private key for cosign key-based signing (optional; keyless OIDC fallback supported).

How to add repository secrets (recommended)
1. Create a branch or work locally on your workstation.
2. Use `gh` CLI from a machine with appropriate permissions:

```bash
# Add DEPLOY_SSH_KEY (private key). Keep the key secure; prefer organization-level secrets for shared use.
gh secret set DEPLOY_SSH_KEY --repo kushin77/self-hosted-runner < /path/to/deploy_id_rsa

# Add PAGERDUTY_TOKEN
gh secret set PAGERDUTY_TOKEN --repo kushin77/self-hosted-runner --body "<token>"

# Add COSIGN_PRIVATE_KEY (base64-encoded PEM)
cat /path/to/cosign.key | base64 | gh secret set COSIGN_PRIVATE_KEY --repo kushin77/self-hosted-runner --body -
```

Rotation guidance
- Rotate keys regularly (90-day recommended). When rotating:
  - Create new key pair, add new secret with temporary name (e.g., `DEPLOY_SSH_KEY_ROTATION`), update workflows to test against the new secret in a canary run, then swap names and remove the old key.
  - For `PAGERDUTY_TOKEN`, create a scoped service token and rotate via PagerDuty UI; update the secret and test with a dry-run incident.

Validation
- Use the `verify-required-secrets` workflow (already included) to validate presence and basic formatting. See `.github/workflows/verify-required-secrets.yml`.
- The **System Status Aggregator** (issue #1064) displays the current credential state every 15 minutes, so you can verify at a glance whether the repository has the required values. When credentials are missing the aggregator reports ❌ and the secret-verifier workflow will open/close issue #1343 automatically.

If you need me to provision a temporary deploy key or rotate keys automatically via automation, comment on issue #1318 and I will coordinate the automated steps.
