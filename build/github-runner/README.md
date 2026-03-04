ElevatedIQ GitHub Runner
=======================

Supervisor & systemd
--------------------

Place the provided systemd unit file at `/etc/systemd/system/elevatediq-github-runner.service` on the host (192.168.168.42), then:

```bash
sudo cp build/github-runner/systemd/elevatediq-github-runner.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now elevatediq-github-runner.service
sudo journalctl -u elevatediq-github-runner.service -f
```

Environment & secrets
---------------------

You can place environment overrides in `/etc/default/elevatediq-github-runner` (e.g. `RUNNER_TOKEN=...` and `GITHUB_URL=...`). The service uses docker compose to start the runner and will respect the `docker-compose.yml` configuration present in this directory.
