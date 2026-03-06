Title: Integrate Vault for secrets and short-lived credentials
Status: open
Assignee: TBD

Description:
- Store runner registration token and service credentials in HashiCorp Vault or Ansible Vault.
- Update Ansible playbooks to read secrets from Vault at runtime.
- Implement access controls and RBAC for secrets access.

Acceptance criteria:
- No secrets in plaintext within repo or CI logs.
- Automated retrieval of secrets for provisioning tasks.
