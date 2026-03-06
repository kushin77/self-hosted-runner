Ansible runner setup
=====================

This folder contains an opinionated Ansible playbook and role to prepare hosts for running `self-hosted-heavy` GitHub Actions workloads.

Files
- `playbooks/setup-self-hosted-heavy.yml` — playbook to apply the `self-hosted-heavy` role to hosts in the `runners` group.
- `roles/self-hosted-heavy/` — role that installs Docker, kind, kubectl, Helm, Terraform, and `gh`.

Workflow
1. Create an inventory listing the runner hosts under group `runners`.
2. Run the playbook with `ansible-playbook -i inventory.ini ansible/playbooks/setup-self-hosted-heavy.yml`.
3. Register the GitHub Actions runner on each host and add labels: `self-hosted`, `linux`, `self-hosted-heavy`.
Ansible playbooks for provisioning self-hosted GitHub Actions runners

Quickstart

1. Copy `ansible/hosts.example` to `ansible/hosts` and update host IPs and vars.
2. Run the playbook (requires ansible installed):

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/provision-self-hosted-runner.yml
```

Notes
- The playbook prompts for a registration token. Generate a repo registration token with:

```bash
gh api --method POST /repos/:owner/:repo/actions/runners/registration-token --jq .token
```

- For non-interactive automation, generate the token and supply via `--extra-vars "reg_token=..."` and modify the playbook to use that var.
