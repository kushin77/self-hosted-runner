**Purpose**

This document outlines the automated steps to clean up the legacy node (192.168.168.31) and migrate responsibilities to the correct worker node (192.168.168.42).

Steps:

1. Review and confirm access:
   - Ensure SSH access to `cloud@192.168.168.31` is available and the deploy key is usable.
2. Run the cleanup playbook (destructive):

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory=ansible/inventory/legacy \
  ansible/playbooks/cleanup-legacy-node.yml -u cloud
```

3. Verify removal on the legacy node:
   - SSH into `192.168.168.31` and confirm `/home/akushnir/runnercloud` is removed and no `node` or `http-server` processes are running.

4. Re-run deployments to the correct worker node (if needed):

```bash
gh workflow run deploy-immutable-ephemeral.yml --repo kushin77/self-hosted-runner --field inventory_file=ansible/inventory/staging
```

5. Confirm services on `192.168.168.42` are healthy and metrics are responding.

Notes:
- This process is destructive on the legacy host. Keep backups if required.
- If you want automation to perform the cleanup without interactive steps, ensure `ANSIBLE_SSH_KEY_PATH` contains the SSH key and run the workflow from GitHub actions.
