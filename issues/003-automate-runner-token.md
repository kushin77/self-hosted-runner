Title: Automate runner registration token provisioning

Description
- Remove manual token prompts from Ansible playbooks and provision tokens via Vault or CI-provided secrets.

Acceptance
- Ansible playbook accepts `runner_registration_token` from extra_vars or a Vault lookup and does not pause for input.
- Document token rotation and least-privilege token generation.

Owner: infra-team
Priority: medium
