Self-hosted-heavy Ansible role
=================================

Purpose
-------
Installs and configures tooling required by the repository `self-hosted-heavy` workflows:
- Docker
- kind
- kubectl
- Helm
- Terraform
- GitHub CLI (`gh`)

Usage
-----
1. Create an inventory with a group `runners` and list the target host(s).
2. Run the playbook as a privileged user (sudo) with a runner system account available.

Example inventory (inventory.ini):

[runners]
runner1.example.com ansible_user=ubuntu

Run the playbook:

```bash
ansible-playbook -i inventory.ini ansible/playbooks/setup-self-hosted-heavy.yml --ask-become-pass
```

Notes
-----
- This role assumes Ubuntu/Debian hosts using `apt`. Adjust tasks if using other distributions.
- The role adds the specified `runner_user` to the `docker` group; ensure your GitHub Actions runner service runs as that user or adjust accordingly.
- Registering the GitHub Actions runner itself requires a registration token from GitHub and is intentionally out-of-band. See the repository `.github/SELF_HOSTED_RUNNERS.md` for labeling and registration steps.
