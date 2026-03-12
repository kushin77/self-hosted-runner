Purpose
- Provide a corrected `systemd` unit and `docker-compose` template for the ElevatedIQ GitHub Actions Runner.
- Include a small helper script to install the unit and compose file on a remote host via SSH.

Notes
- The service crash seen in logs (`Not supported URL scheme http+docker`) indicates an invalid `DOCKER_HOST` or similar environment value. The recommended fix is to use the Docker unix socket: `unix:///var/run/docker.sock`.
- This directory contains templates only. Update `docker-compose.yml` with your runner image, tokens, and secrets before deploying.

Files
- `elevatediq-github-runner.service` — systemd unit that sets `DOCKER_HOST=unix:///var/run/docker.sock` and uses `docker-compose` in the runner working dir.
- `docker-compose.yml` — minimal template for a GitHub Actions runner service (fill in image and envs).
- `fix_runner.sh` — helper script to copy templates to a host and install the unit (does not run automatically; run locally).

Security
- Do not commit tokens or secrets. Use secret manager (GSM/Vault) or bind-mount secret files.

Usage example
1. Inspect and customize `docker-compose.yml`.
2. Run the helper script to copy files and install the service:

```bash
./ops/github-runner/fix_runner.sh --host dev-elevatediq --user akushnir --workdir /home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner
```

3. On the host, verify:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now elevatediq-github-runner.service
sudo journalctl -u elevatediq-github-runner.service -f
```
