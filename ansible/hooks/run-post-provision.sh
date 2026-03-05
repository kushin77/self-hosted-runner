#!/usr/bin/env bash
set -euo pipefail
# Run post-provision smoke checks (expects Ansible inventory configured)
ansible-playbook ansible/playbooks/post-provision.yml --limit workers "$@"
