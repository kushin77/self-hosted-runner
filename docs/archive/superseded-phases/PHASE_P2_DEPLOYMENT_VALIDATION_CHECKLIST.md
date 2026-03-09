# Phase P2 Deployment Validation Checklist

... (existing content)

## Vault AppRole Handoff (Automation)

Starting with this release, AppRole provisioning is automated. Use the helper script to create and hand off credentials to deployment.

```bash
# Create AppRole and write handoff file
bash scripts/automation/pmo/vault-handoff.sh --vault-addr https://vault.example.com

# Source the handoff file for deployment
source /tmp/vault-env.sh

# Run the deployment
./scripts/automation/pmo/deploy-p2-production.sh all
```

Ensure `/tmp/vault-env.sh` is removed after the deployment and rotate secrets per policy.
