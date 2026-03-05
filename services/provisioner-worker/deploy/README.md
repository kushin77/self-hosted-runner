Provisioner-worker staging deploy
================================

This folder contains simple artifacts to deploy `provisioner-worker` to a staging host.

Files:

- `docker-compose.yml` — run worker in a container mounting the repository (useful for quick smoke runs on hosts with Docker).
- `provisioner-worker.service` — systemd unit that runs `worker.js` from a checked-out repo under `/opt/self-hosted-runner`.
- `deploy_to_host.sh` — helper script to SSH to a staging host, clone/update the repo, and start the service (systemd or docker).

Usage (example):

```bash
# Run systemd-based deploy on staging host
./deploy_to_host.sh user@staging.example.com systemd feature/p2-staging-deploy

# Or use docker-compose on a host with Docker
./deploy_to_host.sh user@staging.example.com docker feature/p2-staging-deploy
```

Prereqs on the staging host:

- SSH access with key-based auth.
- Either Docker + docker-compose OR systemd (most Linux distributions).
- **Passwordless sudo** privileges to install the systemd unit (if using
  systemd). The helper script calls `sudo` without supplying a password; if
  your environment prompts you for a password you can run the script as
  root or manually copy/enable the service instead. See the manual example
  below.

Local test note: running the deploy script against `localhost` will also try
  to use `sudo`, which may prompt for a password and therefore fail. In that
  case run the script as root or perform the steps yourself.

Security note: the script clones the public repository and starts the service; for production use, build hardened images and use secret management (Vault AppRole) instead of mounting repo sources directly.
