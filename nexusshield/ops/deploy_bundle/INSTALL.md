# Out-of-band Deployment Bundle — Install Guide

This bundle is intended for direct, out-of-band installation on production hosts when GitHub Actions and PR-based deployment are restricted.

Prereqs (on each host):
- root or sudo access
- `tar`, `sha256sum`, `systemctl`

Steps:

1. Copy and extract the bundle on the host:

```bash
scp admin@fileserver:/path/to/nexusshield-deploy-YYYYmmddT*.tar.gz /tmp/
tar -xzf /tmp/nexusshield-deploy-YYYYmmddT*.tar.gz -C /tmp/nexusshield-deploy
```

2. Install systemd units:

```bash
sudo cp /tmp/nexusshield-deploy/nexusshield/systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nexusshield-credential-rotation.timer
sudo systemctl status nexusshield-credential-rotation.timer
```

3. Install scripts and set permissions:

```bash
sudo mkdir -p /opt/nexusshield
sudo cp -r /tmp/nexusshield-deploy/nexusshield/scripts/* /opt/nexusshield/
sudo chmod +x /opt/nexusshield/*.sh
```

4. Run verification and append immutable audit entry:

```bash
sudo /tmp/nexusshield-deploy/nexusshield/ops/deploy_bundle/verify_and_append_audit.sh /tmp/nexusshield-deploy-YYYYmmddT*.tar.gz
```

5. Confirm audit entry appended to `nexusshield/logs/deployment-audit.jsonl`.

Security notes:
- Do not store service account keys in Git. Use GSM/Vault/KMS for secrets.
- Ensure hosts have network access to GSM/Vault for runtime secret retrieval.
