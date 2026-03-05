# Identity prototypes: Vault Agent & renewal

This directory contains prototype scripts and systemd units used for Phase P4 staging validation of OIDC → Vault workflows.

Files added:

- `vault-oidc-bootstrap.sh` — OIDC login prototype (existing)
- `vault-renewal.sh` — renewal loop prototype (existing)
- `vault-renewal.service` — systemd unit to run the renewal loop (new)
- `metadata-init.sh` — helper that writes metadata-injected files to disk and enables services (new)

Quick staging test (recommended):

1. Ensure `inject_vault_agent_metadata = true` is set in the staging environment module (already set in `terraform/environments/staging-tenant-a/main.tf`).
2. Run `terraform init` and `terraform apply` in the staging environment.
3. Boot an instance from the created template. SSH in.
4. Run the metadata helper manually (if not already invoked by startup):

```bash
sudo /home/ubuntu/scripts/identity/metadata-init.sh
```

Replace path with where `metadata-init.sh` was placed by your startup script. The helper will write:
- `/etc/vault-agent/vault-agent.hcl`
- `/etc/vault-agent/registry-creds.tpl`
- `/etc/systemd/system/vault-agent.service` (if present)
- `/usr/local/bin/vault-renewal.sh` and enable `vault-renewal.service` if present

5. Verify `systemctl status vault-agent.service` and `systemctl status vault-renewal.service`.

Notes:
- Do not store production secrets in instance metadata. This is strictly a staging convenience for testing the flow.
- In production, prefer Workload Identity, instance service accounts, or a secure init flow that retrieves secrets via a short-lived bootstrap token.
