# Deploy managed-auth as API (eiq-api)

This folder contains helper artifacts to deploy the existing `services/managed-auth` service
as the canonical API on port 8080 (`eiq-api` systemd service).

Files:
- `deploy_managed_auth_as_api.sh` - convenience SSH-based deploy script (control host -> worker).
- `eiq-api.service.template` - systemd unit template used by the Ansible playbook.

Recommended usage (from repo root):

1) Quick SSH deploy (non-idempotent; suitable for immediate remediation):

```bash
services/eiq-api/deploy_managed_auth_as_api.sh akushnir /home/akushnir/self-hosted-runner 192.168.168.42
```

2) Idempotent Ansible deploy (preferred for automation):

```bash
ansible-playbook -i inventory/hosts ansible/playbooks/deploy-managed-auth-api.yml
```

After deployment verify:

```bash
ssh akushnir@192.168.168.42 sudo systemctl status eiq-api.service
curl -fsS http://192.168.168.42:8080/health
```
