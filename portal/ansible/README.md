Portal Ansible deploy helpers

Usage:

- Edit `hosts.ini` with your worker hosts (user@host lines).
- From the `portal/ansible` directory run:

```
ansible-playbook -i hosts.ini deploy-portal.yml --extra-vars "alert_webhook='https://hooks.example/xxx'"
```

This playbook will:
- Rsync the portal repo subtree from the control node to each worker (requires control node to have the repo checked out).
- Install the smoke-check systemd service and timer, and optionally configure the `ALERT_WEBHOOK` via systemd drop-in.
