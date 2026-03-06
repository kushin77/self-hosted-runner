Title: Run self-hosted CI with Vault/AppRole secrets configured

Purpose:
- Validate repository workflows and deploy pipelines on our self-hosted runner with Vault/AppRole secrets present.

Tasks:
- Configure temporary secrets on the self-hosted runner environment (VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID or Vault-agent configuration).
- Trigger the main deployment and terraform workflows locally or via the runner.
- Capture logs, failures, and required permissions.
- Create follow-up remediation tasks for workflow failures.

Notes:
- Do NOT commit secret values into the repo. Use runner environment variables or vault-agent config files on the host.
