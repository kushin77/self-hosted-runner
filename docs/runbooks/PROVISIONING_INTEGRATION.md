# Provisioning integration

This repository includes post-provision smoke checks for worker nodes to verify runtime requirements (e.g., Node 20). The recommended integration steps for Packer / CI pipelines:

1. After provisioning a worker or building an image, run the repository hook to execute Ansible post-provision checks:

```bash
# from repo root
packer/hooks/run-post-provision.sh --limit "new-worker-hostname"
```

2. Ensure your CI/pipeline runner has SSH access and an inventory that defines `workers` or pass `-i inventory.ini` to the script.

3. Treat failures as build errors and halt the pipeline. The smoke-playbook will fail if Node < 20 or missing.

Files added:

- `ansible/playbooks/verify-node-20.yml` — smoke playbook
- `ansible/playbooks/post-provision.yml` — imports the smoke playbook
- `ansible/hooks/run-post-provision.sh` — wrapper to run the playbook
- `packer/hooks/run-post-provision.sh` — convenience hook for packer/CI

