**Caddy GitLab Automation**

- Purpose: Ensure `gitlab.internal.elevatediq.com` is proxied by Caddy to the stable
  upstream (`172.17.0.1:8929`) and that the upstream Host header is `192.168.168.42`.
- How it works: an Ansible role `caddy_gitlab` inserts a guarded block into
  `/etc/caddy/Caddyfile.portal.elevatediq` and restarts the `eiq-caddy` container.
- Rollback: run `ansible-playbook playbooks/remove_caddy_gitlab.yml -i <inventory>`
- Recommended follow-ups: add this role to CI/CD or runbooks and create an
  authoritative DNS A record for `gitlab.internal.elevatediq.com`.
