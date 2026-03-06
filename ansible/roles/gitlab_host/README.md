# gitlab_host role

This role manages a temporary `/etc/hosts` entry for the internal GitLab hostname.

Usage

- Set the variable `gitlab_host_ip` (e.g. via inventory/group_vars or `-e`) to the GitLab server IP.
- Optionally override `gitlab_host_name` (defaults to `gitlab.internal.elevatediq.com`).

Example:

ansible-playbook playbooks/add_gitlab_host.yml -e "gitlab_host_ip=10.0.0.42"

Revert:

ansible-playbook playbooks/remove_gitlab_host.yml -e "gitlab_host_ip=10.0.0.42"
