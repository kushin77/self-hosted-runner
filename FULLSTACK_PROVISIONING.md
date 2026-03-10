Fullstack Host Provisioning (Phase 6)
====================================

Purpose
-------
This document explains the minimal, secure, and idempotent steps to prepare an approved fullstack host to run the Phase 6 quickstart and remote-runner.

Quick checklist
---------------
- Run the provisioning script as root on the target host:

```bash
sudo bash /path/to/self-hosted-runner/scripts/provision_fullstack.sh deploy
```

- Ensure the repository is available at `/home/deploy/self-hosted-runner` (git clone or pull)
- Add the deploy user's public key to `/home/deploy/.ssh/authorized_keys` (mode 600)
- Authenticate `gcloud` CLI (if using GCP Secret Manager) or ensure Vault is reachable and `REDACTED_VAULT_TOKEN`/AppRole is configured
- Start the systemd unit once the repo is present:

```bash
sudo systemctl start phase6-quickstart@deploy.service
sudo journalctl -u phase6-quickstart@deploy.service -f
```

Remote-runner invocation (from your workstation)
-----------------------------------------------
If SSH is set up, you can trigger the quickstart remotely from your workstation:

```bash
export FULLSTACK_USER=deploy
export FULLSTACK_HOST=fullstack.example.com
bash scripts/phase6-remote-runner.sh
```

Security notes
--------------
- Never commit secrets to the repository. Use GSM/Vault/KMS.
- The provisioning script intentionally does not auto-authenticate `gcloud` or `vault` for you — these require interactive or secret-backed steps.
