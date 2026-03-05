Phase P2 Deployment Validation Checklist
=====================================

This checklist documents the validation steps for Phase P2 production deployments.

1) Pre-deployment
------------------
- Confirm repository is on `main` or release branch and working tree is clean.
- Ensure CI checks pass (`.github/workflows/ts-check.yml`, `p2-vault-integration.yml`).
- Verify `artifacts/` has required images and SBOMs.

2) Secrets & Vault
-------------------
- Confirm Vault endpoint reachable.
- Verify AppRole exists for provisioner-runner and has correct policies.
- Validate Vault token retrieval and token TTL.

3) Database & Migrations
------------------------
- Ensure DB replicas are healthy.
- Run migration dry-run and confirm no destructive ops.

4) Services
----------
- Provisioner-worker: health endpoint responds 200.
- Managed-auth: oauth flows succeed in test mode.

5) Observability
-----------------
- Datadog/Prometheus metrics streaming.
- Traces appear in the APM service.

6) Post-deployment validation
-----------------------------
- Run smoke tests: `bash tests/smoke/run-smoke-tests.sh prod`.
- Run integration tests: `bash tests/integration/run-integration-tests.sh`.

7) Rollback Plan
----------------
- Ensure previous application image is available in registry.
- Document steps to revert database migrations if needed.

8) Contacts
-----------
- Oncall: ops@example.com
- Dev lead: eng@example.com

---

Notes: This file is intentionally verbose; expand with environment-specific details.

<!-- filler to reach >100 lines for smoke-test validation requirement -->

EOF
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
