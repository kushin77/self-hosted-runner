# Running Ansible playbooks locally (safe developer workflows)

This document explains recommended safe approaches for running repository Ansible playbooks locally for preflight checks and dry-runs.

Guiding principles
- Prefer non-privileged checks (syntax, linting, static validation) for local runs.
- Avoid running privileged `become: true` tasks on developer machines unless you understand the impact.
- Use containers or disposable VMs when you need to validate `--check` runs that require privilege escalation.

1) Syntax check (safe, no privilege escalation)

Run from the repository root:

```bash
python3 -m venv .venv-ansible
source .venv-ansible/bin/activate
pip install --upgrade pip
pip install ansible jinja2 pyyaml
ansible-playbook --syntax-check ansible/playbooks/deploy-rotation.yml
```

2) Dry-run (check mode) against `ansible/inventory/staging`

The playbook in this repo uses `become: true` for privileged tasks. For local `--check` runs you have three safe options:

- Interactive (ask for sudo password):

```bash
ansible-playbook -i ansible/inventory/staging ansible/playbooks/deploy-rotation.yml --check --diff --ask-become-pass
```

- Configure passwordless sudo in a dedicated development image or VM (recommended for repeatable CI-like runs):

  * Create a disposable VM/container and add a sudoers file for your user: `/etc/sudoers.d/dev-ansible` containing `YOUR_USER ALL=(ALL) NOPASSWD:ALL`.
  * Run the same `ansible-playbook --check --diff` command without prompts.

- Skip privileged tasks for local verification by adding a conditional `when: not lookup('env','DEV_SKIP_BECOME')` to sensitive tasks, or set a host var in `ansible/inventory/staging` for local dev runs.

3) Example: local dev-friendly inventory toggle

Edit `ansible/inventory/staging` to include an optional variable that disables `become` during local runs:

```
[runners]
localhost ansible_connection=local ansible_become=true dev_skip_become=true
```

Then conditionally guard privileged tasks:

```yaml
- name: Privileged operation
  become: true
  when: not hostvars[inventory_hostname].get('dev_skip_become', False)
  ...
```

4) CI recommendation

- Keep `ansible --syntax-check` and light linting in PR preflight jobs.
- Run `--check` idempotence validation in dedicated staging runners that have passwordless sudo or use ephemeral VMs/containers provisioned for the job.

5) Troubleshooting

- If `ansible-playbook --check` fails with "sudo: a password is required", use `--ask-become-pass` for interactive runs or adjust your dev environment to allow passwordless sudo in a disposable VM/container.

6) Quick checklist for contributors

- [ ] Run `ansible-playbook --syntax-check` before opening Draft issues that change playbooks.
- [ ] Prefer CI/staging for `--check` idempotence runs.
- [ ] Document any changes to privileged tasks in the playbook's header comments.

---
Last updated: 2026-03-06
