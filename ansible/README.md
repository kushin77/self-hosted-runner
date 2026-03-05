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
