# Vault AppRole Handoff

This document describes the automated Vault AppRole handoff used by the Phase P2 production deployment.

Overview
- The helper script `scripts/automation/pmo/vault-handoff.sh` automates AppRole creation or rotation for the `provisioner-worker` role.
- The script writes a one-time handoff file at `/tmp/vault-env.sh` containing the following exports:
  - `VAULT_ADDR`
  - `VAULT_ROLE_ID`
  - `VAULT_SECRET_ID`

Usage

1. Ensure the Vault CLI is installed and you are authenticated as a Vault admin (or have privileges to enable AppRole and create roles).

```bash
# run from the project root
bash scripts/automation/pmo/vault-handoff.sh --vault-addr https://vault.example.com

# source the generated environment for deployment
source /tmp/vault-env.sh
```

Security and rotation
- `/tmp/vault-env.sh` is created with `chmod 600` and should be removed after use.
- The `secret_id` is short lived (24h by default). Rotate regularly and follow your org's credential management policies.

Integration with deployment
- The deployment orchestrator `scripts/automation/pmo/deploy-p2-production.sh` reads `VAULT_ROLE_ID` and `VAULT_SECRET_ID` from the environment if present.
- To run non-interactively, source `/tmp/vault-env.sh` prior to invoking the deployment script.

Operational notes
- For CI/CD integration, store `VAULT_ROLE_ID` and `VAULT_SECRET_ID` in your secret manager or use dynamic retrieval during runs.
- Consider using Vault Agent or AppRole login in your runtime environment for more secure token handling.

Troubleshooting
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
- See `scripts/automation/pmo/vault-handoff.sh` for CLI logic and explicit commands used.
