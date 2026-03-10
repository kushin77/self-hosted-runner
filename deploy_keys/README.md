Deploy keys for direct-deploy automation

This directory contains public deploy keys that should be installed on target hosts.

How to install for `akushnir@192.168.168.42`:

```bash
mkdir -p ~/.ssh
cat deploy_keys/akushnir_deploy.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Private key remains local at `.ssh/deploy_akushnir_id_ed25519` and is NOT committed.
