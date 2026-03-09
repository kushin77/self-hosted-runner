# Phase P4: Vault Agent Integration Pattern

This doc provides a production pattern to run Vault Agent on runner instances to provision short-lived registry credentials and other secrets.

Files provided:
- `scripts/identity/vault-agent/vault-agent.hcl` — example Vault Agent config (OIDC auto_auth with JWT).
- `scripts/identity/vault-agent/registry-creds.tpl` — template to render registry credentials.
- `scripts/identity/vault-agent/vault-agent.service` — systemd unit to run Vault Agent.

Deployment steps (example):
1. Create a secure path in Vault (KV or dedicated secret engine) to store registry credentials.
2. Configure Vault OIDC/JWT auth method and a role with minimal policies (read access to `secret/data/registries/*`).
3. Bake `vault-agent.hcl` and templates into the instance image or deliver via instance metadata using Terraform `metadata`.
4. Ensure the instance has a secure way to obtain an ID token (Workload Identity Federation, GCP Workload Identity, or cloud-native mechanism). Place the token at `/var/run/secrets/oidc/token`.
5. Start and enable `vault-agent.service` so the agent writes `/etc/runner/registry-creds.json` from the template; the `runner-startup.sh` will then read those creds and log in to the registry.

Security notes:
- Limit Vault policies tightly to the minimum paths and actions.
- Use Vault audit devices and rotate roles/lease TTLs conservatively.
- Prefer Workload Identity Federation to avoid long-lived service account keys.

Example systemd enable commands (run as root on instance):

```bash
sudo cp vault-agent.hcl /etc/vault-agent/vault-agent.hcl
sudo cp registry-creds.tpl /etc/vault-agent/templates/registry-creds.tpl
sudo cp vault-agent.service /etc/systemd/system/vault-agent.service
sudo systemctl daemon-reload
sudo systemctl enable --now vault-agent.service
```
