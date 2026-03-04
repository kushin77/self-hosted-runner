Provisioner Worker deployment

This folder contains simple deployment artifacts for staging or VM-based
environments.

- `docker-compose.yml` — runs `provisioner-worker` container with an `.env` file.
- `provisioner-worker.service` — systemd unit that launches the compose stack

Usage (on a host with Docker and docker-compose):

1. Copy this folder to `/opt/provisioner-worker` on the target host.
2. Create an `.env` file with required variables (e.g. `REDIS_URL`, `METRICS_PORT`).
3. Start via systemd:

```bash
sudo cp -r deploy /opt/provisioner-worker
sudo systemctl daemon-reload
sudo systemctl enable --now provisioner-worker
```

For Kubernetes, create a small Deployment and Service that exposes `METRICS_PORT`.
